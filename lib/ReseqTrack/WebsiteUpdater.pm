package ReseqTrack::WebsiteUpdater;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/website_updater.conf'));
    if (my $log_file = $self->config('hypnotoad_log_file')) {
      $self->log->path($log_file);
    }
    $self->plugin('ForkCall');
    $self->plugin(mail => {
      from => $self->config('email_from'),
      type => 'text/html',
    });

    $self->plugin('ReseqTrack::WebsiteUpdater::Plugins::RateLimiter',
      projects => [keys %{$self->config('projects')}],
      period => $self->config('updating_limiter'),
      );

    $self->routes->post('/update_project/:project')->to(controller => 'website_updater', action=> 'update_project', email_to => $self->config('email_to'));

}

1;
