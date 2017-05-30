package ReseqTrack::WebsiteUpdater::Model::RateLimiter;
use namespace::autoclean;
use Moose;

has '_is_running' => (is => 'rw', isa => 'Bool', default => 0);
has '_stashes' => (is => 'ro', isa => 'ArrayRef[HashRef]', default => sub{return [];});

sub queue {
  my ($self, $stash) = @_;
  push(@{$self->_stashes}, $stash);
}

sub take_stash {
  my ($self) = @_;
  return undef if $self->_is_running;
  my $stash = shift(@{$self->_stashes});
  return undef if !$stash;
  $self->_is_running(1);
  return $stash;
}

sub finished_running {
  my ($self) = @_;
  $self->_is_running(0);
}

__PACKAGE__->meta->make_immutable;

1;
