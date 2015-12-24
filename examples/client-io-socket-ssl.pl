use strict;
use warnings;

use Protocol::HTTP2::Client;
use IO::Socket::SSL;
use IO::Select;

my $host = 'example.com';
my $port = 443;

# POST request
my $h2_client = Protocol::HTTP2::Client->new->request(

    # HTTP/2-headers
    ':method'    => 'POST',
    ':path'      => '/api/datas',
    ':scheme'    => 'https',
    ':authority' => $host . ':' . $port,

    # HTTP-headers
    headers => [
        'user-agent'   => 'Protocol::HTTP2',
        'content-type' => 'application/json'
    ],

    # do something useful with data
    on_done => sub {
        my ( $headers, $data ) = @_;

    },

    # POST body
    data => '{ "data" : "test" }',
);

# TLS transport socket
my $client = IO::Socket::SSL->new(
    PeerHost => $host,
    PeerPort => $port,

    # openssl 1.0.1 support only NPN
    SSL_npn_protocols => ['h2'],

    # openssl 1.0.2 also have ALPN
    #SSL_alpn_protocols => ['h2'],
) or die $!;

# non blocking
$client->blocking(0);

my $sel = IO::Select->new($client);

# send/recv frames until request is done
while ( !$h2_client->shutdown ) {
    $sel->can_write;
    while ( my $frame = $h2_client->next_frame ) {
        syswrite $client, $frame;
    }

    $sel->can_read;
    while ( sysread $client, my $data, 4096 ) {
        $h2_client->feed($data);
    }
}

