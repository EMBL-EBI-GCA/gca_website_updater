requires 'Mojolicious';
requires 'File::Rsync';
requires 'File::Path';
requires 'EnsEMBL::Git';
requires 'Mojolicious::Plugin::ForkCall';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
