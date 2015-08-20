package ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use namespace::autoclean;
use Moose;
use Mojo::UserAgent;
use XML::RSS::Parser;
use FileHandle;

has 'rss' => (is => 'rw', isa => 'Str', required=>1);

sub publish {
  my ($self) = @_;
  return 0 if ! -f $self->rss;

  my $parser = XML::RSS::Parser->new;;
  my $fh = FileHandle->new($self->rss);
  my $feed = $parser->parse_file($fh);

  my $hub_href =  $feed->query('/channel/atom:link[@rel="hub"]/@atom:href');
  return 0 if !$hub_href;
  my $rss_href =  $feed->query('/channel/atom:link[@rel="rel"]/@atom:href');
  return 0 if !hub_href;
  my $ua = Mojo::UserAgent->new()
  my $tx = $ua->post($hub_href, form => {'hub.mode' => 'publish', 'hub.url' => $rss_href});

  return 1 if $tx->success;
  die "pubsubhubbub publish unsuccessulf ".$tx->error->{code};

}




1;
