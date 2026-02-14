use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;
use lib 't/lib';
use PH2Test qw(fake_connect random_string);

subtest 'client large headers' => sub {

    plan tests => 12;

    my $location = "https://www.example.com/";
    my $on_done  = sub {
        my ( $headers, $data ) = @_;
    };
    my %common = (
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        on_done      => $on_done,
    );

    my $server;
    $server = Protocol::HTTP2::Server->new(
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;
            my %h = (@$headers);
            for my $i ( 1 .. 6 ) {
                ok exists $h{"h$i"}, "h$i decoded ok";
            }

            $server->response_stream(
                ':status' => 302,
                stream_id => $stream_id,
                headers   => [
                    location => $location
                ],
            );

        },
    );

    my $client = Protocol::HTTP2::Client->new;
    $client->request(
        %common,
        headers => [
            'h1' => random_string(1000),
            'h2' => random_string(1000),
            'h3' => random_string(1000),
            'h4' => random_string(1000),
            'h5' => random_string(1000),
            'h6' => random_string(1000),
        ],
        ':method' => 'GET',
    )->request(
        %common,
        ':method' => 'GET',
        headers   => [
            'h1' => random_string(5000),
            'h2' => random_string(5000),
            'h3' => random_string(5000),
            'h4' => random_string(5000),
            'h5' => random_string(5000),
            'h6' => random_string(5000),
        ],
    );

    fake_connect( $server, $client );
};

done_testing;
