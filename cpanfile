requires 'Mojolicious';
requires 'File::Rsync';
requires 'EnsEMBL::Git';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
