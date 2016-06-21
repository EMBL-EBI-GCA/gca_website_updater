package ReseqTrack::WebsiteUpdater::Model::Rsyncer;
use namespace::autoclean;
use Moose;
use File::Rsync;

has 'local_dir' => (is => 'rw', isa => 'Str', required => 1);
has 'remote_dests' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub {return []});


# This sub is blocking, so only ever call it from a forked process
# It does not catch errors
sub run {
  my ($self) = @_;

  my $dir = $self->local_dir;
  my $rsync = File::Rsync->new(archive => 1, compress => 1, 'delete-after' => 1);
  foreach my $dest (@{$self->remote_dests}) {
    $rsync->exec(src => $self->local_dir, dest => $dest)
      or die sprintf('could not rsync %s to %s: %s', $self->local_dir, $dest, scalar $rsync->lastcmd);
  }

}

__PACKAGE__->meta->make_immutable;

1;
