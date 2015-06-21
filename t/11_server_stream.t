use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;

sub fake_connect {
    my ( $server, $client ) = @_;

    my ( $clt_frame, $srv_frame );
    do {
        $clt_frame = $client->next_frame;
        $srv_frame = $server->next_frame;
        $server->feed($clt_frame) if $clt_frame;
        $client->feed($srv_frame) if $srv_frame;
    } while ( $clt_frame || $srv_frame );
}

subtest 'server stream' => sub {

    my $server;
    $server = Protocol::HTTP2::Server->new(
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;

            my $s_stream = $server->response_stream(
                ':status' => 200,
                stream_id => $stream_id,

                # HTTP/1.1 Headers
                headers => [
                    'server'        => 'perl-Protocol-HTTP2/0.16',
                    'cache-control' => 'max-age=3600',
                    'date'          => 'Fri, 18 Apr 2014 07:27:11 GMT',
                    'last-modified' => 'Thu, 27 Feb 2014 10:30:37 GMT',
                ],
            );

            isa_ok( $s_stream, 'Protocol::HTTP2::Server::Stream' );
            $s_stream->send('a');
            $s_stream->send('b');
            $s_stream->close;
        },
    );

    my $client = Protocol::HTTP2::Client->new;
    $client->request(

        # HTTP/2 headers
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        ':method'    => 'GET',

        # HTTP/1.1 headers
        headers => [
            'accept'     => '*/*',
            'user-agent' => 'perl-Protocol-HTTP2/0.16',
        ],

        # Callback when receive server's response
        on_done => sub {
            my ( $headers, $data ) = @_;
            is $data, "ab", "stream data ok";
        },
    );

    fake_connect( $server, $client );
};

subtest 'client cancel' => sub {

    my $cancel = 0;
    my $s_stream;
    my $server;
    $server = Protocol::HTTP2::Server->new(
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;

            $s_stream = $server->response_stream(
                ':status' => 200,
                stream_id => $stream_id,

                # HTTP/1.1 Headers
                headers   => [ 'server' => 'perl-Protocol-HTTP2/0.16', ],
                on_cancel => sub {
                    $cancel = 1;
                }
            );

            isa_ok( $s_stream, 'Protocol::HTTP2::Server::Stream' );
            $s_stream->send('a');
        },
    );

    my $client = Protocol::HTTP2::Client->new;
    $client->request(

        # HTTP/2 headers
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        ':method'    => 'GET',

        # HTTP/1.1 headers
        headers => [ 'user-agent' => 'perl-Protocol-HTTP2/0.16', ],

        on_headers => sub {
            is_deeply $_[0],
              [ ':status' => 200, 'server' => 'perl-Protocol-HTTP2/0.16' ],
              "correct headers";
            1;
        },

        # Callback when receive server's response
        on_data => sub {
            my ( $chunk, $headers ) = @_;
            is $chunk, "a", "stream data ok";

            # cancel
            0;
        },
    );

    fake_connect( $server, $client );
    is $cancel, 1, "successfully canceled";
};

done_testing;
