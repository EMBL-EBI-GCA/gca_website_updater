package ReseqTrack::WebsiteUpdater::Model::GitUpdater;
use namespace::autoclean;
use Moose;
use EnsEMBL::Git qw();

has 'branch' => (is => 'rw', isa => 'Maybe[Str]');
has 'remote' => (is => 'rw', isa => 'Maybe[Str]');
has 'directory' => (is => 'rw', isa => 'Str', required => 1);
has 'rsync_dests' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub {return []});

has '_start_branch' => (is => 'rw', isa => 'Str');

# This sub is blocking, so only ever call it from a forked process
# It does not catch errors
sub run {
  my ($self) = @_;

  my $branch = $self->branch($self->branch // 'master');
  my $remote = $self->remote($self->remote // 'origin');

  my $dir = $self->directory;
  chdir $dir or die $@;
  EnsEMBL::Git::is_git_repo() or die ("$dir is not a git repo");
  EnsEMBL::Git::is_tree_clean() or die ("$dir is not clean");

  my $start_branch = EnsEMBL::Git::current_branch();
  if (!$start_branch || $start_branch eq 'HEAD') {
    die 'HEAD is currently not on any branch. If you are in middle of a rebase or merge, please fix or abort it before continuing.'
  }
  $self->_start_branch($start_branch);

  EnsEMBL::Git::fetch();
  EnsEMBL::Git::checkout_tracking($branch, $remote) or return ("could not checkout $branch on $remote $dir");

  if (!EnsEMBL::Git::can_fastforward_merge($branch, $remote, 1)) {
    # local is behind or diverged (can_fastforward_merge return true if local branch is ahead of remote)
    if (!EnsEMBL::Git::ff_merge("$remote/$branch")) {
      # this will fail if branches are diverged
        die "Branch '$branch' is diverged from remote. Please do a `git pull --rebase` on '$branch' before continuing.";
    }
  }

}

sub cleanup {
  my ($self) = @_;
  return if !$self->_start_branch;
  return if $self->_start_branch eq $self->branch;
  EnsEMBL::Git::checkout($self->_start_branch);
}

__PACKAGE__->meta->make_immutable;

1;
