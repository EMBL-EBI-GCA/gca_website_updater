package ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer;
use namespace::autoclean;
use Moose;
use Mojo::Util qw(slurp spurt url_unescape);
use XML::Twig;
use HTTP::Tiny;
use JSON qw(encode_json decode_json);
use Encode qw();
use HTML::Entities qw();

has 'site_dir' => (is => 'rw', isa => 'Str', required=>1);
has 'index' => (is => 'rw', isa => 'Str', required=>1);
has 'type' => (is => 'rw', isa => 'Str', default => 'sitemap');
has 'hosts' => (is => 'rw', isa => 'ArrayRef[Str]', required=>1);
has 'filter_tags' => (is => 'rw', isa => 'ArrayRef[Str]', default => sub {return []});
has 'error_callback' => (is => 'rw', isa => 'CodeRef');

sub error {
  my ($self, $string) = @_;
  if (my $cb = $self->error_callback) {
    $cb->($string);
  }
}

# This sub is blocking, so only ever call it from a forked process
sub run {
  my ($self) = @_;
  eval {
    my $index = $self->build_index;
    foreach my $host (@{$self->hosts}) {
      $self->load_index($host, $index);
    }

  };
  if ($@) {
    $self->error($@);
  }

}

sub load_index {
  my ($self, $es_host, $index) = @_;
  my %existing_urls;
  my $ua = HTTP::Tiny->new();
  my $base_url = sprintf('http://%s', $es_host);
  my $index_type_base_url = sprintf('%s/%s/%s', $base_url, $self->index, $self->type);
  my $response = $ua->post("$index_type_base_url/_search?search_type=scan&scroll=1m", {
    content => encode_json({query => {match_all => {}}}),
  });
  my $scroll_id = decode_json($response->{content})->{_scroll_id};
  die "did not get scroll id" if !$scroll_id;
  SCROLL:
  while(1) {
    $response = $ua->post("$base_url/_search/scroll?scroll=1m", {content => $scroll_id});
    my $json = decode_json($response->{content}) or die "could not decode ".$response->{content};
    my $hits = $json->{hits}{hits};
    last SCROLL if !@$hits;
    foreach my $hit (@$hits) {
      if (my $page_details = $index->{$hit->{_source}{url}}) {
        $ua->post(sprintf("%s/%s/_update", $index_type_base_url, $hit->{_id}),
            {content => encode_json({doc => $page_details})});
        $existing_urls{$hit->{_source}{url}} = 1;
      }
      else {
        $ua->delete(sprintf("%s/%s", $index_type_base_url, $hit->{_id}));
      }
    }
    $scroll_id = $json->{_scroll_id};
  }
  URL:
  while (my ($url, $page_details) = each %$index) {
    next URL if $existing_urls{$url};
    $ua->post(sprintf("%s/", $index_type_base_url),
          {content => encode_json($page_details)});
  }
}

sub build_index {
  my ($self) = @_;
  my $site_dir = $self->site_dir;
  die "did not find directory $site_dir"  if ! -d $site_dir;
  die "did not find sitemap $site_dir/sitemap.xml"  if ! -f "$site_dir/sitemap.xml";
  my $twig = XML::Twig::->new;
  $twig->parsefile("$site_dir/sitemap.xml");
  my %es_index;
  foreach my $url ($twig->root->findvalues('/urlset/url/loc')) {
    my $path = url_unescape($url);
    $path =~ s{^http://[^/]*}{};
    $path = $site_dir.$path;
    $path = Encode::decode('UTF-8', $path);
    if (-d $path) {
      $path .= '/index.html';
    }
    my $content = slurp($path) or die "could not slurp $path $!";

    my ($title) = $content =~ m{<title(?: [^>]*)?>(.*?)</title(?: [^>]*)?>}s;

    $content = HTML::Entities::decode_entities($content);
    foreach my $tag (@{$self->filter_tags}) {
      $content =~ s{<$tag(?: [^>]*)?>.*?</$tag(?: [^>]*)?>}{}gs;
    }
    $content =~ s{<[^<>]+>}{}gs;
    $content =~ s{\s+}{ }gs;

    $es_index{$url} = {content => $content, title => $title, url => $url};

  }
  return \%es_index;
}

__PACKAGE__->meta->make_immutable;

1;
