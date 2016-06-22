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
    1.b. Queues up a delayed job if the project is already updating
    1.c. ..or exits if a job is already queued
  2. Uses the GitUpdater module to pull updates from git
  3. Uses the Jekyll module to build the static content from the git repo
  4. Uses the Rsyncer module to copy the jekyll _site directory to the webserver directories
  5. Uses the ElasticSitemapIndexer to put the static content into elasticsearch. This enables site search.
  6. Uses the PubSubHubBub module to announce updates to the rss feeds. This triggers automatic tweets.

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

    $rate_limiter->begin;
    if ($rate_limiter->time_to_sleep){
      $self->render(text => sprintf('update will run in %s seconds', $rate_limiter->time_to_sleep));
    }
    else {
      $self->render(text => 'update will run now');
    }
    return if $rate_limiter->is_queuing;

    Mojo::IOLoop->delay(sub {
      my ($delay) = @_;
      if ($rate_limiter->is_running) {
        $rate_limiter->queue;
        Mojo::IOLoop->timer($rate_limiter->time_to_sleep => $delay->begin);
      }
      else {
        $delay->pass;
      }
    },
    sub {
      my ($delay) = @_;
      $rate_limiter->run;
      $self->stash(rate_limiter => $rate_limiter);
      my $git_updater = ReseqTrack::WebsiteUpdater::Model::GitUpdater->new(
            branch => $project_config->{branch},
            remote => $project_config->{remote},
            directory => $project_config->{git_directory},
          );
      # Put the git updater on delay->data so destructor gets called when loop has finished.
      $delay->data(git_updater => $git_updater);
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
        }, [], $delay->begin(1)
      );
    },
    sub {
      my ($delay, $err) = @_;
      die $err if $err;
      $self->fork_call(sub {eval {$delay->data('git_updater')->cleanup;};}, [], sub {return;});
      $rate_limiter->finished_running;
    })->catch(sub {
      my ($delay, $err) = @_;
      if (my $git_updater = $delay->data('git_updater')) {
        $self->fork_call(sub {eval {$git_updater->cleanup;};}, [], sub {return;});
      }
      $self->handle_error($err);
      $rate_limiter->unset;
    });

  };
  if ($@) {
    $self->handle_error($@);
    $self->render(text => 'server error', status => 500);
  }
}

sub handle_error {
  my ($self, $error) = @_;
  $self->app->log->error($error);
  if (my $rate_limiter = $self->stash('rate_limiter')) {
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
}

1;
