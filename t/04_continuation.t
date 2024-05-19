use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Constants qw(const_name :endpoints :states);

BEGIN {
    use_ok('Protocol::HTTP2::Connection');
}

done_testing;
__END__
subtest 'decode_continuation_request' => sub {

    open my $fh, '<:raw', 't/continuation.request.data' or die $!;
    my $data = do { local $/; <$fh> };

    my $con = Protocol::HTTP2::Connection->new( SERVER,
        on_change_state => sub {
            my ( $stream_id, $previous_state, $current_state ) = @_;
            printf "Stream %i changed state from %s to %s\n",
              $stream_id, const_name( "states", $previous_state ),
              const_name( "states", $current_state );
        },
        on_error => sub {
            fail("Error occurred");
        }
    );
    my $offset = $con->preface_decode( \$data, 0 );
    is( $offset, 24, "Preface exists" ) or BAIL_OUT "preface?";
    while ( my $size = $con->frame_decode( \$data, $offset ) ) {
        $offset += $size;
    }
    is $con->error, 0, "no errors";
};

done_testing;
