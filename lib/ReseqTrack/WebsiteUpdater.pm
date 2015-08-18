package ReseqTrack::WebsiteUpdater;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->get('/update_project/:project')->to(controller => 'websiteupdater', action=> 'update_project');

}

1;
