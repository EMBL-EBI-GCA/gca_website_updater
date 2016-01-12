package ReseqTrack::WebsiteUpdater::Controller::WebsiteUpdater;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop;
use Mojo::Util qw(slurp spurt);
use EnsEMBL::Git;
use File::Rsync;
use File::Path;
use ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer;

sub update_project {
  my ($self) = @_;
  my $project = $self->stash('project');
  my $project_config = $self->config('projects')->{$project};
  return $self->render(text=>"project $project does not exist\n", status=>404) if !$project_config;

  my $log_dir = $self->config('updating_log_dir') || $self->app->home->rel_dir('var/run');
  File::Path::make_path($log_dir);
  my $updating_limiter = $self->stash('updating_limiter') || 120;

  
  my $log_file = "$log_dir/$project.log";
  my $current_time = time();
  if (-f $log_file) {
    my $line = slurp($log_file) or return $self->server_error("could not slurp from $log_file $!");
    if ($line && $line =~ /queue (\d+)/) {
      my $queue_time = $1;
      my $time_to_sleep = $queue_time + $updating_limiter - $current_time;
      return $self->render(text => "update will run in $time_to_sleep seconds\n");
    }
    if ($line && $line =~ /running (\d+)/) {
      my $running_time = $1;
      my $time_to_sleep = $running_time + $updating_limiter - $current_time;
      if ($time_to_sleep > 0) {
        $self->render(text => "update will run in $time_to_sleep seconds\n");
        spurt("queue $running_time\n", $log_file) or return $self->server_error("could not spurt to $log_file $!");
        Mojo::IOLoop->timer($time_to_sleep => sub {
          $current_time = time();
          spurt("running $current_time\n", $log_file) or return $self->app->log->info("could not spurt to $log_file $!");
          $self->run_git_update({callback => \&run_pubsubhubbub, callback_args => [$project_config]});
        });
        return;
      }
    }
  }

  spurt("running $current_time\n", $log_file) or return $self->server_error("could not spurt to $log_file $!");
  $self->render(text => "update will run now\n");

  $self->run_git_update(
    {callback => \&run_pubsubhubbub, callback_args => [$project_config]},
    {callback => \&run_es_sitemap, callback_args => [$project_config]},
    );

}

sub run_pubsubhubbub {
  my ($self, $project_config) = @_;
  my $rss = $project_config->{'pubsubhubbub'};
  return if !$rss;
  my $dir = $project_config->{'git_directory'};
  my $pubsubhubbub = ReseqTrack::WebsiteUpdater::Model::PubSubHubBub->new(
    rss => "$dir/_site/$rss",
    error_callback => sub {$self->app->log->info(@_)},
  );

  $self->fork_call( sub {
    my ($pubsubhubbub) = @_;
    $pubsubhubbub->publish();
  }, [$pubsubhubbub], sub {return;}
  );

}

sub run_es_sitemap {
  my ($self, $project_config) = @_;
  my $es_sitemap_index = $project_config->{'es_sitemap_index'};
  return if !$es_sitemap_index;
  my $dir = $project_config->{'git_directory'};
  my $es_sitemap_indexer = ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer->new(
    index => $self->stash('project'),
    hosts => $es_sitemap_index->{'hosts'},
    search_index_file => join('/', $project_config->{'git_directory'}, '_site', $es_sitemap_index->{'search_index_file'}),
    error_callback => sub {$self->app->log->info(@_);},
  );

  $self->fork_call( sub {
    my ($es_sitemap_indexer) = @_;
    $es_sitemap_indexer->run();
  }, [$es_sitemap_indexer], sub {return;}
  );

}

sub run_git_update {
  my ($self, @callbacks) = @_;

  $self->fork_call( sub {
    my ($self) = @_;
    my $project = $self->stash('project');
    my $project_config = $self->config('projects')->{$project};
    my $dir = $project_config->{'git_directory'} or return $self->app->log->info("no git_directory for $project");

    my $git_branch = $project_config->{branch} || 'master';
    my $git_remote = $project_config->{remote} || 'origin';

    chdir $dir or return ("could not change to $dir");


    is_git_repo() or return ("$dir is not a git repo");
    is_tree_clean() or return ("$dir is not clean");

    my $start_branch = current_branch();
    if (!$start_branch || $start_branch eq 'HEAD') {
      return ("HEAD is currently not on any branch. If you are in middle of a rebase or merge, please fix or abort it before continuing.");
    }

    fetch();
    checkout_tracking($git_branch, $git_remote) or return ("could not checkout $git_branch on $git_remote $dir");

    sub reset_and_return {
      my (@returns) = @_;
      checkout($start_branch) if $git_branch ne $start_branch;
      return @returns;
    }

    if (!can_fastforward_merge($git_branch, $git_remote, 1)) {
      # local is behind or diverged (can_fastforward_merge return true if local branch is ahead of remote)
      if (!ff_merge("$git_remote/$git_branch")) {
        # this will fail if branches are diverged
          reset_and_return("Branch '$git_branch' is diverged from remote. Please do a `git pull --rebase` on '$git_branch' before continuing.");
      }
    }

    system('bundle exec jekyll build');
    reset_and_return("failed to build jekyll: $!") if $?;
    if (my $signal = $? & 127) {
      reset_and_return("jekyll exited with with $signal");
    }
    if (my $exit = $? >>8) {
      reset_and_return("jekyll exited with code $exit");
    }

    my $rsync = File::Rsync->new(archive => 1, compress => 1, 'delete-after' => 1);
    foreach my $dest (@{$project_config->{rsync_dests}}) {
      $rsync->exec(src => "$dir/_site/", dest => $dest) or reset_and_return("could not rsync $dir/_site/ to $dest ". scalar $rsync->lastcmd);
    }

    reset_and_return();
  },
  [$self],
  sub {
    my ($self, @handler_args) = @_;
    if (@handler_args) {
      $self->app->log->info(@handler_args);
      return;
    }
    foreach my $callback_hash (@callbacks) {
      if (my $callback = $callback_hash->{callback}) {
        $callback->($self, @{$callback_hash->{callback_args}});
      }
    }

  });


}

sub server_error {
  my ($self, $msg) = @_;
  $self->app->log->info($msg);
  return $self->render(text=>"server error, see log file for details\n", status=>500);
}

1;
