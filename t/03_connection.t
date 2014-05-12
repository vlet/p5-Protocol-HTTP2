use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Constants qw(const_name :endpoints :states);
use lib 't/lib';
use PH2Test;

BEGIN {
    use_ok('Protocol::HTTP2::Connection');
}

subtest 'decode_request' => sub {

    my $data = hstr(<<EOF);
        5052 4920 2a20 4854 5450 2f32 2e30 0d0a
        0d0a 534d 0d0a 0d0a 000a 0400 0000 0000
        0300 0000 6404 0000 ffff 0038 0105 0000
        0001 4189 128d f07c 1f19 a400 0f83 0608
        2f4c 4943 454e 5345 8856 032a 2f2a 548a
        abdd 97e5 352b e162 5cbf 7f00 8dba aadc
        ebc8 e0fc 0f86 6d1d ff8f
EOF

    my $run_test = sub { };
    my $con = Protocol::HTTP2::Connection->new( SERVER,
        on_change_state => sub {
            my ( $stream_id, $previous_state, $current_state ) = @_;
            printf "Stream %i changed state from %s to %s\n",
              $stream_id, const_name( "states", $previous_state ),
              const_name( "states", $current_state );

            if ( $current_state == HALF_CLOSED ) {
                $run_test->($stream_id);
            }
        },
        on_error => sub {
            fail("Error occured");
        }
    );

    my $run_test_flag = 0;

    $run_test = sub {
        my $stream_id = shift;
        is_deeply(
            $con->stream_headers($stream_id),
            [
                ':authority'      => '127.0.0.1:8000',
                ':method'         => 'GET',
                ':path'           => '/LICENSE',
                ':scheme'         => 'http',
                'accept'          => '*/*',
                'accept-encoding' => 'gzip, deflate',
                'user-agent'      => 'nghttp2/0.4.0-DEV',
            ],
            "correct request headers"
        ) and $run_test_flag = 1;
    };

    my $offset = $con->preface_decode( \$data, 0 );
    is( $offset, 24, "Preface exists" ) or BAIL_OUT "preface?";
    while ( my $size = $con->frame_decode( \$data, $offset ) ) {
        $offset += $size;
    }
    ok( $con->error == 0 && $run_test_flag, "decode headers" );
    $data   = hstr("0000 0401 0000 0000");
    $offset = 0;
    while ( my $size = $con->frame_decode( \$data, $offset ) ) {
        $offset += $size;
    }
    ok( $con->error == 0 );

    $data   = hstr("0008 0700 0000 0000 0000 0000 0000 0000");
    $offset = 0;
    while ( my $size = $con->frame_decode( \$data, $offset ) ) {
        $offset += $size;
    }
    ok( $con->error == 0 );
};

subtest 'decode_response' => sub {

    my $data = hstr(<<EOF);
0005 0400 0000 0000 0300 0000 64
EOF

    my $con = Protocol::HTTP2::Connection->new(CLIENT);

    # Emulate request
    my $sid = $con->new_stream;
    $con->stream_state( $sid, HALF_CLOSED );

    my $run_test_flag = 0;
    $con->stream_cb(
        $sid, CLOSED,
        sub {

            is_deeply(
                $con->stream_headers($sid),
                [
                    ':status'        => 200,
                    'server'         => 'nghttpd nghttp2/0.4.0-DEV',
                    'content-length' => 46,
                    'cache-control'  => 'max-age=3600',
                    'date'           => 'Fri, 18 Apr 2014 07:27:11 GMT',
                    'last-modified'  => 'Thu, 27 Feb 2014 10:30:37 GMT',
                ],
                "correct response headers"
            ) and $run_test_flag = 1;
        }
    );

    my $offset = 0;
    while ( my $size = $con->frame_decode( \$data, $offset ) ) {
        $offset += $size;
    }
    ok( $con->error == 0 );

    $data = hstr(<<EOF);
    0000 0401 0000 0000 0052 0104 0000 0001
    8877 93ba aadc ebe9 35d5 56e7 5e47 07e0
    7c33 68ef fc7f 0f0f 0234 365a 89b5 3d33
    26a5 ce88 803f 6494 d383 3298 6436 7bf0
    3100 c060 8e62 8e61 136a d747 7094 a2be
    394c 519b 4af7 9880 6030 84c8 0991 19b5
    6ba3 002e 0000 0000 0001 6e61 6d65 203d
    2022 5072 6f74 6f63 6f6c 2d48 5454 5032
    220a 2320 6261 6467 6573 203d 205b 2274
    7261 7669 7322 5d0a 0000 0001 0000 0001
EOF

    $offset = 0;
    while ( my $size = $con->frame_decode( \$data, $offset ) ) {
        $offset += $size;
    }
    is $offset, length($data), "read all data";
    ok( $con->error == 0 && $run_test_flag );

};

done_testing();
