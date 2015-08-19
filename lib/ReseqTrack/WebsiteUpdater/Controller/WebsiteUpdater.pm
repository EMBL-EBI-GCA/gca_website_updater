package ReseqTrack::WebsiteUpdater::Controller::WebsiteUpdater;
use Mojo::Base 'Mojolicious::Controller';
use EnsEMBL::Git;
use File::Rsync;

sub update_project {
  my ($self) = @_;

  $self->inactivity_timeout(120);
  $self->fork_call( sub {
    my ($self) = @_;

    my $project = $self->stash('project');
    my $project_config = $self->config('projects')->{$project};
    return(\&not_found, "no project config for $project") if !$project_config;

    my $git_branch = $project_config->{branch} || 'master';
    my $git_remote = $project_config->{remote} || 'origin';

    my $dir = $project_config->{'git_directory'} or return (\&server_error, "no git_directory for $project");
    chdir $dir or return (\&server_error, "could not change to $dir");


    is_git_repo() or return (\&server_error, "$dir is not a git repo");
    is_tree_clean() or return (\&server_error, "$dir is not clean");

    my $start_branch = current_branch();
    if (!$start_branch || $start_branch eq 'HEAD') {
      return (\&server_error, "HEAD is currently not on any branch. If you are in middle of a rebase or merge, please fix or abort it before continuing.");
    }

    fetch();
    checkout_tracking($git_branch, $git_remote) or return (\&server_error, "could not checkout $git_branch on $git_remote $dir");

    sub reset_and_return {
      my (@returns) = @_;
      checkout($start_branch) if $git_branch ne $start_branch;
      return @returns;
    }

    if (!can_fastforward_merge($git_branch, $git_remote, 1)) {
      # local is behind or diverged (can_fastforward_merge return true if local branch is ahead of remote)
      if (!ff_merge("$git_remote/$git_branch")) {
        # this will fail if branches are diverged
          reset_and_return(\&server_error, "Branch '$git_branch' is diverged from remote. Please do a `git pull --rebase` on '$git_branch' before continuing.");
      }
    }

    system('bundle exec jekyll build');
    reset_and_return(\&server_error, "failed to build jekyll: $!") if $?;
    if (my $signal = $? & 127) {
      reset_and_return(\&server_error, "jekyll exited with with $signal");
    }
    if (my $exit = $? >>8) {
      reset_and_return(\&server_error, "jekyll exited with code $exit");
    }

    my $rsync = File::Rsync->new(archive => 1, compress => 1, 'delete-after' => 1);
    foreach my $dest (@{$project_config->{rsync_dests}}) {
      $rsync->exec(src => "$dir/_site/", dest => $dest) or reset_and_return(\&server_error, "could not rsync $dir/_site/ to $dest ". scalar $rsync->lastcmd);
    }
    reset_and_return();;
  },
  [$self],
  sub {
    my ($self, $handler, @handler_args) = @_;
    return $handler->($self, @handler_args) if defined $handler;
    $self->render(text=>"success\n");
  };


}

sub not_found {
  my ($self, $msg) = @_;
  $self->app->log->info($msg);
  return $self->render(text=>"not found, see log file for details", status=>404);
}

sub server_error {
  my ($self, $msg) = @_;
  $self->app->log->info($msg);
  return $self->render(text=>"server error, see log file for details\n", status=>500);
}


1;
