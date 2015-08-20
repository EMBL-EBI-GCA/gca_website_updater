package ReseqTrack::WebsiteUpdater::Controller::WebsiteUpdater;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop;
use Mojo::Util qw(slurp spurt);
use EnsEMBL::Git;
use File::Rsync;
use File::Path;
use JSON qw();

sub update_project {
  my ($self) = @_;

  my $project = $self->stash('project');
  my $project_config = $self->config('projects')->{$project};
  return $self->render(text=>"project $project does not exist\n", status=>404) if !$project_config;

  my $req_json;
  eval { $req_json = JSON::decode_json($self->req->body); };
  return $self->render(text => 'error encoutered while parsing JSON', status => 400) if $@;
  return $self->render(text=>"not parsing failed builds\n") if $req_json->{'error'};

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
          $self->update_project_now();
        });
        return;
      }
    }
  }

  spurt("running $current_time\n", $log_file) or return $self->server_error("could not spurt to $log_file $!");
  $self->render(text => "update will run now\n");
  $self->update_project_now();
}


sub update_project_now {
  my ($self) = @_;

  $self->fork_call( sub {
    my ($self) = @_;
    my $project = $self->stash('project');
    my $project_config = $self->config('projects')->{$project};
    my $git_branch = $project_config->{branch} || 'master';
    my $git_remote = $project_config->{remote} || 'origin';

    my $dir = $project_config->{'git_directory'} or return ("no git_directory for $project");
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

    if (my $rss = $self->config('pubsubhubbub')) {
      my $pubsubhubbub = ReseqTrack::WebsiteUpdater::Model::PubSubHubBub->new(
        rss => "$dir/_site/$rss",
      );
      eval{$pubsubhubbub->publish or die "publish did not work";};
      reset_and_return("error encoutered while publishing to pubsubhubbub: $@") if $@;
    }

    reset_and_return();
  },
  [$self],
  sub {
    my ($self, @handler_args) = @_;
    if (@handler_args) {
      $self->app->log->info(@handler_args);
    }
  });


}

sub server_error {
  my ($self, $msg) = @_;
  $self->app->log->info($msg);
  return $self->render(text=>"server error, see log file for details\n", status=>500);
}

1;
