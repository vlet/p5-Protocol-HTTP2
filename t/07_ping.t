use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2Test;
use Protocol::HTTP2::Constants qw(const_name :frame_types :endpoints :states
  :flags);
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;

subtest 'ping' => sub {

    my $client = Protocol::HTTP2::Client->new;
    $client->request(
        ':authority' => 'localhost',
        ':method'    => 'GET',
        ':path'      => '/',
        ':scheme'    => 'https',
    );

    my $server = Protocol::HTTP2::Server->new;

    while ( my $frame = $client->next_frame ) {
        $server->feed($frame);
        while ( $frame = $server->next_frame ) {
            $client->feed($frame);
        }
    }

    $client->ping("HELLOSRV");
    my $ping = $client->next_frame;
    ok binary_eq( $ping, hstr("0000 0806 0000 0000 0048 454c 4c4f 5352 56") ),
      "ping";
    $server->feed($ping);
    ok binary_eq( $ping = $server->next_frame,
        hstr("0000 0806 0100 0000 0048 454c 4c4f 5352 56") ),
      "ping ack";
    is $server->next_frame, undef;
    $client->feed($ping);
    is $client->next_frame, undef;
};

subtest 'dont mess with continuation' => sub {
    my $con = Protocol::HTTP2::Connection->new(CLIENT);
    $con->preface(1);

    $con->new_stream(1);
    my @hdrs = ( HEADERS, 0, 1, { hblock => \"\x82" } );
    my @cont = ( CONTINUATION, END_HEADERS, 1, \"\x85" );
    my @data = ( DATA, 0, 1, \"DATA" );

    $con->enqueue( @hdrs, @cont, @data );

    ok binary_eq( $con->dequeue, $con->frame_encode(@hdrs) ), "1-HEADER";

    my @ping = ( PING, 0, 0, \"HELLOSRV" );
    $con->enqueue_first(@ping);

    ok binary_eq( $con->dequeue, $con->frame_encode(@cont) ), "2-CONTINUATION";
    ok binary_eq( $con->dequeue, $con->frame_encode(@ping) ), "3-PING";
    ok binary_eq( $con->dequeue, $con->frame_encode(@data) ), "4-DATA";
};

done_testing
