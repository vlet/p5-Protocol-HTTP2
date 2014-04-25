package Protocol::HTTP2::Frame::Blocked;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    if ( $length > 0 ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    # TODO: issue WINDOW_UPDATE frame or set SETTINGS_INITIAL_WINDOW_SIZE

    return 0;
}

sub encode {
    return '';
}

1;
