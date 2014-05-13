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
    my $server = Protocol::HTTP2::Server->new;

    while ( my $frame = $client->next_frame ) {
        $server->feed($frame);
        while ( $frame = $server->next_frame ) {
            $client->feed($frame);
        }
    }

    my $ping = $client->{con}->frame_encode( PING, 0, 0, \"HELLOSRV" );
    ok binary_eq( $ping, hstr("0008 0600 0000 0000 4845 4c4c 4f53 5256") ),
      "ping";
    $server->feed($ping);
    ok binary_eq( $ping = $server->next_frame,
        hstr("0008 0601 0000 0000 4845 4c4c 4f53 5256") ),
      "ping ack";
    is $server->next_frame, undef;
    $client->feed($ping);
    is $client->next_frame, undef;
};

subtest 'dont mess with continuation' => sub {
    my $con = Protocol::HTTP2::Connection->new(CLIENT);
    $con->dequeue;    # PREFACE
    $con->dequeue;    # SETTINGS

    $con->new_stream(1);
    my $hdrs = $con->frame_encode( HEADERS,      0,           1, \"\x82" );
    my $cont = $con->frame_encode( CONTINUATION, END_HEADERS, 1, \"\x85" );
    my $data = $con->frame_encode( DATA,         0,           1, \"DATA" );

    $con->enqueue( $hdrs, $cont, $data );

    ok binary_eq( $con->dequeue, $hdrs ), "1-HEADER";

    my $ping = $con->frame_encode( PING, 0, 0, \"HELLOSRV" );
    $con->enqueue_first($ping);

    ok binary_eq( $con->dequeue, $cont ), "2-CONTINUATION";
    ok binary_eq( $con->dequeue, $ping ), "3-PING";
    ok binary_eq( $con->dequeue, $data ), "4-DATA";
};

done_testing
