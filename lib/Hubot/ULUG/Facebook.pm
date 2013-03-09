package Hubot::ULUG::Facebook;
use 5.014;
use utf8;

use Moose;
use AnyEvent;

#use AnyEvent::Log;
#$AnyEvent::Log::FILTER->level('trace');

use Data::Dump qw(dd pp);

use Array::Diff;
use Facebook::Graph;
use Module::Util;
use YAML::Tiny;

has 'conf',
    is => 'ro',
    lazy_build => 1;

has 'fb',
    is => 'ro',
    lazy_build => 1;

has 'cv',
    is => 'rw',
    default => sub { +{} };

sub _build_conf  { YAML::Tiny->read('ulug.yml')->[0] }
sub _build_fb    {
    my $conf = shift->conf;

    Facebook::Graph->new(
        app_id       => $conf->{id},
        secret       => $conf->{secret},
        access_token => $conf->{access_token},
    );
}

sub load {
    my ($self, $robot) = @_;

    die "ulug: Only IRC adapter is supported"
        unless ref $robot->adapter eq 'Hubot::Adapter::Irc';

    $self->cv->{loop} = (AE::timer 0, 20, sub {
        $robot->brain->save;
        $self->update($robot);
    });
}

sub update {
    my ($self, $robot) = @_;

    AE::log debug => 'start';

    $self->facebook_query(sub {
        my $stream = shift;

        my $diff = Array::Diff->diff(
            $robot->brain->{ulug}{fb}{ids} // [],
            $stream->{ids}                 // [],
        )->added;

        push @{$robot->brain->{ulug}{fb}{ids}}, @$diff;

        for my $id (@$diff) {
            next if $robot->brain->{ulug}{fb}{$id};
            $robot->brain->{ulug}{fb}{$id} = time;

            $self->facebook_query_id($id, sub {
                my $row = shift;

                my $abbr = $row->{message};
                $abbr =~ s/\s+/ /gs;
                $abbr =~ m/(.{0,70})/;
                $abbr = $1;

                my $notice = sprintf "[페이스북] %s\: %s… at %s",
                    $abbr,
                    $row->{created_time},
                    $row->{from}{name};

                $robot->adapter->emit(ulug_notify => $notice);
            });
        }
    });
}


# Query the recent facebook streams, yield the result to the callback

sub facebook_query {
    my ($self, $cb) = @_;

    my $req = $self->fb->query->find($self->conf->{group_id})
        ->include_metadata
        ->select_fields('feed')
        ->where_since('-1 day')
        ->date_format('M j, h:i A')
        ->limit_results(4)
        ->request;

    my $w; $w = $req->cb(sub {
        my $res = shift->recv;
        my $stream = $res->as_hashref->{feed}{data};

        # let's reorder the structure
        my %tidy; 
        $tidy{all} = $stream;
        $tidy{ids} = [ map $_->{id}, @$stream ];

        $cb->( \%tidy );
    });

    $self->cv->{fb_query} = $w;
}


# Query the facebook with specific data id, yield the result to the callback

sub facebook_query_id {
    my ($self, $id, $cb) = @_;

    my $req = $self->fb->query->find($id)
        ->include_metadata
        ->select_fields('message', 'from', 'created_time')
        ->date_format('M j, h:i A')
        ->limit_results(3)
        ->request;

    my $w; $w = $req->cb(sub {
        my $row = shift->recv;
        $row = $row->as_hashref;

        $cb->( $row );
    });

    $self->cv->{fb_query_id} = $w;
}

__PACKAGE__->meta->make_immutable;
1;
