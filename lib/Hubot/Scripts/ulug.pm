package Hubot::Scripts::ulug;

use strict;
use warnings;

use Encode qw(encode);
use Module::Util qw(find_in_namespace);

my @plugin;

sub load {
    my ($class, $robot) = @_;

    _hack($robot);

    # Load Hubot::ULUG::* modules here.

    my @module = find_in_namespace('Hubot::ULUG');

    for my $m (@module) {
        my $ret    = eval "require $m";
        my $plugin = $m->new;

        if ($@) {
            print STDERR "$m died while being loaded: $@";
            next;
        }
        unless ($ret) {
            print STDERR "$m returned false while being loaded. Skiped.\n";
            next;
        }

        push @plugin, $plugin;
        $plugin->load($robot);
    }
}


# XXX - Hubot does not provide to broadcast message to rooms.

sub _hack {
    my ($robot) = @_;

    die "ulug: Only IRC Adapter is supported"
        unless $robot->adapter->isa('Hubot::Adapter::Irc');

    my @rooms = split ",", $ENV{HUBOT_IRC_ROOMS};

    $robot->adapter->on(ulug_notify => sub {
        my ($self, $msg) = @_;

        for (@rooms) { 
            $robot->adapter->irc->send_srv(PRIVMSG => $_, encode("UTF-8", $msg));
        }
    });
}

1;

=head1 NAME

Hubot::Scripts::ulug

=head1 SYNOPSIS

    hubot ulug - No command provided

=head1 DESCRIPTION

These commands are grabbed from pod at the C<SYNOPSIS> section each file.

=head1 AUTHOR

Hyungsuk Hong <am0c@perl.kr>

=cut
