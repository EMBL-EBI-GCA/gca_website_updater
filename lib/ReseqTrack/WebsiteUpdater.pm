package ReseqTrack::WebsiteUpdater;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/website_updater.conf'));

    $self->routes->get('/update_project/:project')->to(controller => 'website_updater', action=> 'update_project');

}

1;
