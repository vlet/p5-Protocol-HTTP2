use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2Test;
use Protocol::HTTP2::Constants qw(const_name :frame_types :endpoints :states
  :flags);
use Protocol::HTTP2::Connection;

subtest 'priority frame' => sub {

    my $con = Protocol::HTTP2::Connection->new(SERVER);

    my $frame = $con->frame_encode( PRIORITY, 0, 1, [ 0, 32 ] );
    ok binary_eq( $frame, hstr("0000 0502 0000 0000 0100 0000 001f") ),
      "PRIORITY";

    # Simulate client request
    $con->preface(1);
    $con->new_peer_stream(1);

    my $res = $con->frame_decode( \$frame, 0 );
    is $res, 14, "decoded correctly";

    $frame = $con->frame_encode( HEADERS,
        END_HEADERS,
        1,
        {
            hblock     => \hstr("41 8aa0 e41d 139d 09b8 f000 0f82 8486"),
            stream_dep => 0,
            weight     => 32
        }
    );

    ok binary_eq(
        $frame,
        hstr(
                "0000 1401 2400 0000 0100 0000 001f 418a"
              . "a0e4 1d13 9d09 b8f0 000f 8284 86"
        )
      ),
      "Headers with priority";

    $res = $con->frame_decode( \$frame, 0 );
    is $res, 29, "decoded correctly";
};

subtest 'stream reprioritization' => sub {

    my $con = Protocol::HTTP2::Connection->new(SERVER);

    # Simulate client request
    $con->preface(1);
    $con->new_peer_stream(1);
    $con->new_peer_stream(3);
    $con->new_peer_stream(5);

    #    0
    #   /|\
    #  1 3 5

    ok $con->stream_reprio( 1, 1, 0 ), "stream_reprio exclusive 1 done";

    #   1
    #  / \
    # 3   5

    is $con->stream(1)->{stream_dep}, 0, "1 on top";
    is $con->stream(3)->{stream_dep}, 1, "3 under 1";
    is $con->stream(5)->{stream_dep}, 1, "5 under 1";

    $con->new_peer_stream(7);
    ok $con->stream_reprio( 7, 0, 1 ), "stream_reprio 7";
    $con->new_peer_stream(9);
    ok $con->stream_reprio( 9, 0, 7 ), "stream_reprio 9";
    $con->new_peer_stream(11);
    ok $con->stream_reprio( 11, 0, 9 ), "stream_reprio 11";

    ok $con->stream_reprio( 1, 0, 9 ), "stream_reprio 1 under 9";

    #
    #    1                  9
    #  / | \              /   \
    # 3  5  7            11    1
    #        \     =>        / | \
    #         9             3  5  7
    #          \
    #          11

    is $con->stream(9)->{stream_dep},  0, "9 on top";
    is $con->stream(11)->{stream_dep}, 9, "11 under 9";
    is $con->stream(1)->{stream_dep},  9, "1 under 9";
    is $con->stream(3)->{stream_dep},  1, "3 under 1";
    is $con->stream(5)->{stream_dep},  1, "3 under 1";
    is $con->stream(7)->{stream_dep},  1, "7 under 1";

    #diag explain $con->{streams};
};

done_testing;
