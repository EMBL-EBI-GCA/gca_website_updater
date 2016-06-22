package ReseqTrack::WebsiteUpdater::Plugins::RateLimiter;
use Mojo::Base qw{ Mojolicious::Plugin };
use ReseqTrack::WebsiteUpdater::Model::RateLimiter;

sub register {
    my ($self, $app, $args) = @_;

    my $projects = $args->{projects} // [];
    my %hash;
    foreach my $project (@$projects) {
      $hash{$project} = ReseqTrack::WebsiteUpdater::Model::RateLimiter->new(
        period => $args->{period}
      );
    }

    $app->{_rate_limiter_hash} = \%hash;
    $app->helper(rate_limiter => sub {
      my ($c, $project) = @_;
      return $app->{_rate_limiter_hash}{$project};
    });

}

1;
