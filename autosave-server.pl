#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use YAML::Syck;

my $config_file = "$FindBin::Bin/autosave-server.yml";
my $config = -e $config_file ? LoadFile $config_file : {};
   $config->{port}        ||= 9999;
   $config->{interval}    ||= 1;
   $config->{emacsclient} ||= '/Applications/Emacs.app/Contents/MacOS/bin/emacsclient';

package Autosave;
use Moose;
use List::Rubyish;

extends 'Tatsumaki::Application';
has files => (
    is      => 'rw',
    isa     => 'List::Rubyish',
    default => sub { List::Rubyish->new([]) },
);

no Moose;
__PACKAGE__->meta->make_immutable;

sub add_file {
    my ($self, $file) = @_;
    if ($file && !$self->files->find(sub { $file eq $_ })) {
        $self->files->push($file);
        printf STDERR "added: $file\n"
    }
}

sub save_file {
    my $self  = shift;
    if ($self->files->size) {
        my $elisp = $self->elisp;
        `$config->{emacsclient} -ne '$elisp'`;
    }
}

sub elisp {
    my $self = shift;
    my $elisp = <<'EOS';
(mapc (lambda (file)
        (save-current-buffer
            (let ((buffer (get-file-buffer file)))
              (when buffer
                (set-buffer buffer)
                (when (buffer-modified-p)
                  (save-buffer))))))
      (list "%s"))
EOS
    sprintf $elisp, $self->files->join('" "');
}

package MainHandler;
use parent qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    $self->write('<ul>');
    $self->application->files->each(
        sub {
            $self->write(<<"EOS");
<li>$_</li>
EOS
            }
    );
    $self->write('</ul>');
}

package AddHandler;
use parent qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    $self->application->add_file($self->request->param('file'));
    $self->write('ok');
}

package main;
use AnyEvent;
use Tatsumaki::Server;

my $app = Autosave->new([
    '/add' => 'AddHandler',
    '/'    => 'MainHandler',
]);
my $timer  = AE::timer 0 => $config->{interval} => sub { $app->save_file };
my $server = Tatsumaki::Server->new(port => $config->{port});
   $server->register_service($app);

AE::cv->recv;
