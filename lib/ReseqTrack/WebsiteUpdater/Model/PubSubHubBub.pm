package ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use namespace::autoclean;
use Moose;
use XML::RSS::Parser;
use FileHandle;
use HTTP::Tiny;

has 'rss' => (is => 'rw', isa => 'Str', required=>1);

# This sub is blocking, so only ever call it from a forked process
sub publish {
  my ($self) = @_;
  my $rss = $self->rss;
  die "did not find file $rss"  if ! -f $rss;

  my $parser = XML::RSS::Parser->new;;
  my $fh = FileHandle->new($rss);
  my $feed = $parser->parse_file($fh);

  my $hub_href =  $feed->query('/channel/atom:link[@rel="hub"]/@atom:href');
  die "no hub link in rss feed $rss" if !$hub_href;
  my $rss_href =  $feed->query('/channel/atom:link[@rel="self"]/@atom:href');
  die "no self link in rss feed $rss"  if !$rss_href;

  my $response = HTTP::Tiny->new->post_form($hub_href, {'hub.mode'=> 'publish', 'hub.url' => $rss_href});
  die "post to $hub_href failed: ".$response->{status}.$response->{content} if  $response->{status} !~ /^2\d\d$/;

  #Feedburner
  my $feedrss_href = $rss_href;
  $feedrss_href =~ s/rss\.xml//;
  #http://www.feedburner.com/fb/a/pingSubmit?bloglink=http://www.hipsci.org/announcements
  my $feedburner_href = 'http://www.feedburner.com/fb/a/pingSubmit?bloglink='.$feedrss_href;

  my $feedburner_response = HTTP::Tiny->new->get($feedburner_href);
  die "ping to $feedburner_href failed: ".$$feedburner_response->{status}.$$feedburner_response->{content} if  $$feedburner_response->{status} !~ /^2\d\d$/;

}

__PACKAGE__->meta->make_immutable;

1;
