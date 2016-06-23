package ReseqTrack::WebsiteUpdater::Model::RateLimiter;
use namespace::autoclean;
use Moose;

has 'is_running' => (is => 'rw', isa => 'Bool', default => 0);
has 'is_queuing' => (is => 'rw', isa => 'Bool', default => 0);

sub run {
  my ($self) = @_;
  $self->is_running(1);
  $self->is_queuing(0);
}

sub queue {
  my ($self) = @_;
  $self->is_queuing(1);
}

sub finished_running {
  my ($self) = @_;
  $self->is_running(0);
}

__PACKAGE__->meta->make_immutable;

1;
