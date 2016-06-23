package ReseqTrack::WebsiteUpdater::Controller::WebsiteUpdater;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop;
use ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer;
use ReseqTrack::WebsiteUpdater::Model::GitUpdater;
use ReseqTrack::WebsiteUpdater::Model::Rsyncer;
use ReseqTrack::WebsiteUpdater::Model::Jekyll;
use Mojo::IOLoop::ForkCall;

=pod

This controller basically does this:
  1. Queries the rate limiter to find out if the project is already updating
    1.b. Queues a new job and exits if a job is already queued
  2. Uses the GitUpdater module to pull updates from git
  3. Uses the Jekyll module to build the static content from the git repo
  4. Uses the Rsyncer module to copy the jekyll _site directory to the webserver directories
  5. Uses the ElasticSitemapIndexer to put the static content into elasticsearch. This enables site search.
  6. Uses the PubSubHubBub module to announce updates to the rss feeds. This triggers automatic tweets.
  7. Repeat 2-6 if a new job has been queued since the update began

Steps 2-6 get executed in a forked process because they are blocking.

Errors get emailed to users, set in the config file

=cut


sub update_project {
  my ($self) = @_;
  eval {
    my $project = $self->stash('project');
    my $project_config = $self->config('projects')->{$project};
    return $self->reply->not_found if !$project_config;
    $self->stash(project_config => $project_config);

    my $rate_limiter = $self->rate_limiter($project);
    die "did not get rate limiter for $project" if !$rate_limiter;

    if ($rate_limiter->is_running){
      $self->render(text => 'OK: an update is already running, so this update will run immediately afterwards.');
      $rate_limiter->queue;
      return;
    }
    else {
      $self->render(text => 'update will run now');
    }

    my $git_updater = ReseqTrack::WebsiteUpdater::Model::GitUpdater->new(
      branch => $project_config->{branch},
      remote => $project_config->{remote},
      directory => $project_config->{git_directory},
    );

    $self->stash(git_updater => $git_updater);
    $self->stash(rate_limiter => $rate_limiter);

    $self->_run_update_process;

  };
  if ($@) {
    $self->_handle_error($@);
    $self->render(text => 'server error', status => 500);
  }
}

sub _run_update_process {
  my ($self) = @_;
  my $rate_limiter = $self->stash('rate_limiter');
  my $project_config = $self->stash('project_config');
  my $git_updater = $self->stash('git_updater');

  $rate_limiter->run;

  $self->fork_call( 
    sub { eval {
      $git_updater->run;
      ReseqTrack::WebsiteUpdater::Model::Jekyll->new(
            directory => $project_config->{git_directory},
          )->run;
      
      ReseqTrack::WebsiteUpdater::Model::Rsyncer->new(
            local_dir => $project_config->{git_directory} .'/_site/',
            remote_dests => $project_config->{rsync_dests},
          )->run;

      if (my $es_sitemap_index = $project_config->{'es_sitemap_index'}) {
        ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer->new(
          index => $self->stash('project'),
          hosts => $es_sitemap_index->{'hosts'},
          search_index_file => join('/', $project_config->{'git_directory'}, '_site', $es_sitemap_index->{'search_index_file'}),
        )->run();
      }

      if (my $rss = $project_config->{'pubsubhubbub'}) {
        ReseqTrack::WebsiteUpdater::Model::PubSubHubBub->new(
          rss => sprintf('%s/_site/%s', $project_config->{git_directory}, $rss),
        )->publish;
      }
      };
      return $@;
    }, [], sub {
      my ($err) = @_;
      eval {
        die $err if $err;
        $rate_limiter->finished_running;
        if ($rate_limiter->is_queuing) {
          return $self->_run_update_process;
        }
      };
      if ($@) {
        $self->handle_error($@);
      }
    }
  );
}

sub handle_error {
  my ($self, $error) = @_;
  $self->app->log->error($error);
  my $rate_limiter = $self->stash('rate_limiter');
  if ($rate_limiter) {
    $rate_limiter->finished_running;
  }
  my $project_config = $self->stash('project_config');
  if (my $email_to = $project_config->{email_to}) {
    $self->mail(
      to => $email_to,
      subject => 'Error in the website updater for project '.$self->stash('project'),
      data => $error,
    );
  }
  if ($rate_limiter && $rate_limiter->is_queuing) {
    $self->_run_update_process;
  }
}

1;
