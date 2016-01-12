requires 'Mojolicious';
requires 'File::Rsync';
requires 'File::Path';
#requires 'EnsEMBL::Git';
requires 'Mojolicious::Plugin::ForkCall';
requires 'namespace::autoclean';
requires 'Moose';
requires 'XML::RSS::Parser';
requires 'FileHandle';
requires 'HTTP::Tiny';
requires 'IO::Socket::SSL';
requires 'HTML::Entities';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
