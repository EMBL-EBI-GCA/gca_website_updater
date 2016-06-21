package ReseqTrack::WebsiteUpdater::Model::RateLimiter;
use namespace::autoclean;
use Moose;
use Mojo::Util qw();

has 'period' => (is => 'rw', isa => 'Int', default => 120);
has 'log_file' => (is => 'rw', isa => 'Str', required => 1);

has 'continue' => (is => 'rw', isa => 'Bool', default => 0);
has 'time_to_sleep' => (is => 'rw', isa => 'Int', default => 0);

sub spurt {
  my ($self, $text) = @_;
  Mojo::Util::spurt($text, $self->log_file) or die sprintf('could not spurt to %s %s', $self->log_file, $!);
}

sub slurp {
  my ($self) = @_;
  my $log_file = $self->log_file;
  return if ! -f $log_file;
  Mojo::Util::slurp($self->log_file) or die sprintf('could not slurp from %s %s', $self->log_file, $!);
}

sub wait {
  my ($self) = @_;

  $self->period($self->period // 120);

  my $current_time = time();
  my $line = $self->slurp;

  if (!$line) {
    return $self->continue(1);
  }

  if ($line =~ /queue (\d+)/) {
    my $queue_time = $1;
    $self->time_to_sleep($1 + $self->period - $current_time);
    # Do not call the callback
    return;
  }

  $line =~ /running (\d+)/;
  my $running_time = $1 // die "error parsing line: $line";
  my $time_to_sleep = $running_time + $self->period - $current_time;

  if ($time_to_sleep <= 0) {
    return $self->continue(1);
  }

  $self->time_to_sleep($time_to_sleep);
  $self->spurt("queue $running_time\n");
}

sub begin {
  my ($self) = @_;
  my $current_time = time();
  $self->spurt("running $current_time\n");
}

__PACKAGE__->meta->make_immutable;

1;
