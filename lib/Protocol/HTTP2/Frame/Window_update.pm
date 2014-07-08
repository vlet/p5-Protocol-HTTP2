package Protocol::HTTP2::Frame::Window_update;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :limits);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    my $fcw_add = unpack 'N', substr $$buf_ref, $buf_offset, 4;
    $fcw_add &= 0x7FFF_FFFF;

    if ( $frame_ref->{stream} == 0 ) {
        if ( $con->fcw_send($fcw_add) > MAX_FCW_SIZE ) {
            $con->error(FLOW_CONTROL_ERROR);
        }
        else {
            $con->send_blocked();
        }
    }
    else {
        my $fcw = $con->stream_fcw_send( $frame_ref->{stream}, $fcw_add );
        if ( defined $fcw && $fcw > MAX_FCW_SIZE ) {
            $con->stream_error( $frame_ref->{stream}, FLOW_CONTROL_ERROR );
        }
        elsif ( defined $fcw ) {
            $con->stream_send_blocked( $frame_ref->{stream} );
        }
    }
    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    return pack 'N', $data;
}

1;
