use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;
use lib 't/lib';
use PH2Test qw(fake_connect);

subtest 'client POST' => sub {

    plan tests => 6;

    my $body     = "DATA" x 10_000;
    my $location = "https://www.example.com/";
    my $on_done  = sub {
        my ( $headers, $data ) = @_;
        my %h = (@$headers);
        is $h{location}, $location, "correct redirect";
    };
    my %common = (
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        headers      => [],
        on_done      => $on_done,
    );

    my $server;
    $server = Protocol::HTTP2::Server->new(
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;
            my %h = (@$headers);

            if ( $h{':method'} eq 'POST' ) {
                is $body, $data, 'received correct POST body';
            }
            elsif ( $h{':method'} eq 'PUT' ) {
                is $body, $data, 'received correct PUT body';
            }
            elsif ( $h{':method'} eq 'OPTIONS' ) {
                is $data, undef, 'no body for OPTIONS';
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
        ':method' => 'POST',
        data      => $body,
      )->request( %common, ':method' => 'OPTIONS', )->request(
        %common,
        ':method' => 'PUT',
        data      => $body,
      );

    fake_connect( $server, $client );
};

done_testing;
