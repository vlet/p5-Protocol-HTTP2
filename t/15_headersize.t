use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;
use Protocol::HTTP2::Constants qw(:errors :settings :limits);
use lib 't/lib';
use PH2Test qw(fake_connect random_string);

subtest 'hpack bomb' => sub {

    plan tests => 1;
    my $hc = 2000;

    my $server;
    $server = Protocol::HTTP2::Server->new(
        on_error => sub {
            my $error = shift;
            is $error, &ENHANCE_YOUR_CALM, "ENHANCE_YOUR_CALM error";
        },
        on_request => sub {
            ok 0, "request should not have been received"
        }
    );

    my $client = Protocol::HTTP2::Client->new;
    $client->request(
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        ':method' => 'GET',
        headers   => [ ('a' => '')x$hc ],
    );

    fake_connect( $server, $client );
};

subtest 'change settings' => sub {

    plan tests => 3;
    my $hc = 2000;

    my $server;
    $server = Protocol::HTTP2::Server->new(
        settings => {
            &SETTINGS_MAX_HEADER_LIST_SIZE => $hc*33 + 200
        },
        on_error => sub {
            my $error = shift;
            ok 0, "should be no error";
        },
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;
            my %h = (@$headers);
            is $#$headers, 2*($hc+4)-1, "2*($hc + 4) headers";
            is keys %h, 5, "merged in 1 + 4 headers";
            ok exists $h{b}, "b header";
        }
    );

    my $client = Protocol::HTTP2::Client->new;
    $client->request(
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        ':method' => 'GET',
        headers   => [ ('b' => '')x$hc ],
    );

    fake_connect( $server, $client );
};


done_testing;
