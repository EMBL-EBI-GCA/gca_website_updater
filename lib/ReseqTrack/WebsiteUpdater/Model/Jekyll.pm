package ReseqTrack::WebsiteUpdater::Model::Jekyll;
use namespace::autoclean;
use IPC::Cmd qw();
use Moose;

has 'directory' => (is => 'rw', isa => 'Str', required => 1);

# This sub is blocking, so only ever call it from a forked process
# It does not catch errors
sub run {
  my ($self) = @_;

  my $dir = $self->directory;
  chdir $dir or die $@;

  my ($success, $error_message, $full_buf, $stdout_buf, $stderr_buf) =
    IPC::Cmd::run(command => 'bundle exec jekyll build');
  die join("\n", $error_message, @$stderr_buf) if !$success;

}

__PACKAGE__->meta->make_immutable;

1;
