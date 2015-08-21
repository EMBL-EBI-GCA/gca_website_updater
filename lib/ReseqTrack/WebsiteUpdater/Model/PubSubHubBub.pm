package ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use namespace::autoclean;
use Moose;
use XML::RSS::Parser;
use FileHandle;

has 'rss' => (is => 'rw', isa => 'Str', required=>1);
has 'success_callback' => (is => 'rw', isa => 'CodeRef');
has 'error_callback' => (is => 'rw', isa => 'CodeRef');

sub error {
  my ($self, $string) = @_;
  if (my $cb = $self->error_callback) {
    $cb->($string);
  }
}

sub publish {
  my ($self) = @_;
  eval {
    my $rss = $self->rss;
    die "did not find file $rss"  if ! -f $rss;

    my $parser = XML::RSS::Parser->new;;
    my $fh = FileHandle->new($rss);
    my $feed = $parser->parse_file($fh);

    my $hub_href =  $feed->query('/channel/atom:link[@rel="hub"]/@atom:href');
    die "no hub link in rss feed $rss" if !$hub_href;
    my $rss_href =  $feed->query('/channel/atom:link[@rel="self"]/@atom:href');
    die "no self link in rss feed $rss"  if !$rss_href;
    system("curl -XPOST -i $hub_href -d 'hub.mode=publish&hub.url=$rss_href'");
    die("failed to run curl $hub_href: $!") if $?;
    if (my $signal = $? & 127) {
      die("curl exited with with $signal");
    }
    if (my $exit = $? >>8) {
      die("curl exited with code $exit");
    }

  };
  if ($@) {
    $self->error($@);
  }

}




1;
