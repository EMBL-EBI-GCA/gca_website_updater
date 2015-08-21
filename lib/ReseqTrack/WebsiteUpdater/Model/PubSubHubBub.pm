package ReseqTrack::WebsiteUpdater::Model::PubSubHubBub;
use namespace::autoclean;
use Moose;
use Mojo::UserAgent;
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
  my ($self, %args) = @_;
  eval {
    my $rss = $self->rss;
    die "did not find file $rss"  if ! -f $rss;

    my $parser = XML::RSS::Parser->new;;
    my $fh = FileHandle->new($rss);
    my $feed = $parser->parse_file($fh);

    my $hub_href =  $feed->query('/channel/atom:link[@rel="hub"]/@atom:href');
    die "no hub link in rss feed" if !$hub_href;
    my $rss_href =  $feed->query('/channel/atom:link[@rel="rel"]/@atom:href');
    die "no rel link in rss feed"  if !$rss_href;
    my $ua = Mojo::UserAgent->new()
    my $tx = $ua->post($hub_href, form => {'hub.mode' => 'publish', 'hub.url' => $rss_href}
        => sub {
            my ($ua, $tx) = @_;
            if ($tx->success) {
              if (my $callback = $args->{success_callback}) {
                $callback->($tx->res->content->body);
              }
            }
            else {
              $self->error("pubsubhubbub publish unsuccessulf ".$tx->error->{code}.': '.$tx->res->content->body);
              }
            }
        );

    $ua->ioloop->start if !$ua->ioloop->is_running;
  };
  if ($@) {
    $self->error($@);
  }

}




1;
