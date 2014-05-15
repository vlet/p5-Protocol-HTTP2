use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2Test;
use Protocol::HTTP2::Constants qw(const_name :frame_types :endpoints :states
  :flags :errors);
use Protocol::HTTP2::Connection;

subtest 'altsvc frame' => sub {

    my $con = Protocol::HTTP2::Connection->new(CLIENT);

    my $frame = $con->frame_encode( ALTSVC, 0, 1,
        {
            max_age => 2,
            port    => 8000,
            host    => 'localhost',
            proto   => 'https',
            origin  => 'https://blabla.com:3500',    # ignored
        }
    );

    ok binary_eq(
        $frame,
        hstr(
            <<"EOF"
        0017 0a00 0000 0001     # Frame header
        0000 0002               # max_age
        1f40                    # port
        00                      # -
        05                      # proto length
        6874 7470 73            # "https"
        09                      # host length
        6c6f 6361 6c68 6f73 74  # "localhost"
EOF
        )
      ),
      "ALTSVC encoded well";

    # Simulate client request
    $con->preface(1);
    $con->new_stream(1);
    $con->stream_state( 1, HALF_CLOSED );

    my $res = $con->frame_decode( \$frame, 0 );
    is $res, 31, "ALTSVC decoded well";

};

subtest 'altsvc frame not for SERVER' => sub {
    my $con = Protocol::HTTP2::Connection->new(SERVER);
    my $frame = $con->frame_encode( ALTSVC, 0, 0,
        {
            port  => 8000,
            host  => 'localhost',
            proto => 'https',
        }
    );

    # Simulate client request
    $con->preface(1);
    $con->new_peer_stream(1);
    $con->stream_state( 1, HALF_CLOSED );

    my $res = $con->frame_decode( \$frame, 0 );
    is $res, undef, "error occured";
    is $con->error, PROTOCOL_ERROR, "protocol error";

};

done_testing;
