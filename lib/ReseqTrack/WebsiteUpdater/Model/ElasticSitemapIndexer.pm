package ReseqTrack::WebsiteUpdater::Model::ElasticSitemapIndexer;
use namespace::autoclean;
use Moose;
use Mojo::Util qw(slurp);
use HTTP::Tiny;
use Mojo::JSON qw(encode_json decode_json);
use HTML::Entities qw();

has 'index' => (is => 'rw', isa => 'Str', required=>1);
has 'type' => (is => 'rw', isa => 'Str');
has 'hosts' => (is => 'rw', isa => 'ArrayRef[Str]', required=>1);
has 'search_index_file' => (is => 'rw', isa => 'Str', required=>1);

# This sub is blocking, so only ever call it from a forked process
# It does not catch errors
sub run {
  my ($self) = @_;

  $self->type($self->type // 'sitemap');

  my $index = $self->build_index;
  foreach my $host (@{$self->hosts}) {
    $self->load_index($host, $index);
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
  my $search_index_file = $self->search_index_file;
  die "did not find file $search_index_file"  if ! -f $search_index_file;

  my $search_json = slurp($search_index_file) or die "could not slurp $search_index_file $!";
  my $search_array = decode_json($search_json);
  my %es_index;
  foreach my $page (@$search_array) {
    $page->{content} = HTML::Entities::decode_entities($page->{content});
    $es_index{$page->{url}} = $page;
  }
  return \%es_index;
}

__PACKAGE__->meta->make_immutable;

1;
