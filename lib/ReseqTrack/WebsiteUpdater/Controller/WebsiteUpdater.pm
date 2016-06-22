package ReseqTrack::WebsiteUpdater::Controller::WebsiteUpdater;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop;
use File::Path;
use ReseqTrack::WebsiteUpdater::Model::RateLimiter;
use ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer;
use ReseqTrack::WebsiteUpdater::Model::GitUpdater;
use ReseqTrack::WebsiteUpdater::Model::Rsyncer;
use ReseqTrack::WebsiteUpdater::Model::Jekyll;

sub update_project {
  my ($self) = @_;
  eval {
    my $project = $self->stash('project');
    my $project_config = $self->config('projects')->{$project};
    return $self->reply->not_found if !$project_config;
    my $log_dir = $self->config('updating_log_dir') || $self->app->home->rel_dir('var/run');
    File::Path::make_path($log_dir);

    my $rate_limiter = ReseqTrack::WebsiteUpdater::Model::RateLimiter->new(
      period => $self->config('updating_limiter'),
      log_file => sprintf('%s/%s.log', $log_dir, $project),
      );
    $rate_limiter->wait;
    if ($rate_limiter->time_to_sleep){
      $self->render(text => sprintf('update will run in %s seconds', $rate_limiter->time_to_sleep));
    }
    else {
      $self->render(text => 'update will run now');
    }
    return if !$rate_limiter->continue;

    Mojo::IOLoop->delay(sub {
      my ($delay) = @_;
      Mojo::IOLoop->timer($rate_limiter->time_to_sleep => $delay->begin);
    },
    sub {
      my ($delay) = @_;
      $rate_limiter->begin;
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
    })->catch(sub {
      my ($delay, $err) = @_;
      if (my $git_updater = $delay->data('git_updater')) {
        $self->fork_call(sub {eval {$git_updater->cleanup;};}, [], sub {return;});
      }
      $self->handle_error($err);
      $self->app->log->error($@);
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
  $self->mail(
    subject => 'Error in the static website updater for project '.$self->stash('project'),
    data => $error,
  );
}

1;
