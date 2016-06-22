package ReseqTrack::WebsiteUpdater::Model::RateLimiter;
use namespace::autoclean;
use Moose;

has 'period' => (is => 'rw', isa => 'Int', default => 120);

has 'is_running' => (is => 'rw', isa => 'Bool', default => 0);
has 'is_queuing' => (is => 'rw', isa => 'Bool', default => 0);
has 'time_to_sleep' => (is => 'rw', isa => 'Int', default => 0);

has '_run_time' => (is => 'rw', isa => 'Int', predicate => 'has_run_time');
has '_current_time' => (is => 'rw', isa => 'Int');

sub begin {
  my ($self) = @_;
  my $current_time = $self->_current_time(time());
  my $time_to_sleep = $self->has_run_time ? $self->_run_time + $self->period - $current_time : 0;
  $time_to_sleep = $time_to_sleep < 0 ? 0 : $time_to_sleep;

  $self->time_to_sleep($time_to_sleep);
}

sub run {
  my ($self) = @_;
  $self->is_running(1);
  $self->is_queuing(0);
  $self->_run_time(time());
}

sub queue {
  my ($self) = @_;
  $self->is_running(0);
  $self->is_queuing(1);
}

sub finished_running {
  my ($self) = @_;
  $self->is_running(0);
}

__PACKAGE__->meta->make_immutable;

1;
