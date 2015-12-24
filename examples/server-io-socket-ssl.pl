use strict;
use warnings;
use IO::Select;
use IO::Socket::SSL;
use Protocol::HTTP2::Server;

# TLS transport socket
my $srv = IO::Socket::SSL->new(
    LocalAddr     => '0.0.0.0:4443',
    Listen        => 10,
    SSL_cert_file => 'test.crt',
    SSL_key_file  => 'test.key',

    # openssl 1.0.1 support only NPN
    SSL_npn_protocols => ['h2'],

    # openssl 1.0.2 also have ALPN
    #SSL_alpn_protocols => ['h2'],
) or die $!;

# Accept client connection
while ( my $client = $srv->accept ) {

    # HTTP/2 server
    my $h2_srv;
    $h2_srv = Protocol::HTTP2::Server->new(
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;
            $h2_srv->response(
                ':status' => 200,
                stream_id => $stream_id,
                headers   => [
                    'server'       => 'Protocol::HTTP2::Server',
                    'content-type' => 'application/json',
                ],
                data => '{ "hello" : "world" }',
            );
        }
    );

    # non-blocking
    $client->blocking(0);
    my $sel = IO::Select->new($client);

    # send/recv frames until request/response is done
    while ( !$h2_srv->shutdown ) {
        $sel->can_write;
        while ( my $frame = $h2_srv->next_frame ) {
            syswrite $client, $frame;
        }

        $sel->can_read;
        my $len;
        while ( my $rd = sysread $client, my $data, 4096 ) {
            $h2_srv->feed($data);
            $len += $rd;
        }

        # check if client disconnects
        last unless $len;
    }

    # destroy server object
    undef $h2_srv;
}

