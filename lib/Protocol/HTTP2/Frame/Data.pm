package Protocol::HTTP2::Frame::Data;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :settings :limits);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my ( $pad, $offset ) = ( 0, 0 );
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # DATA frames MUST be associated with a stream
        $frame_ref->{stream} == 0
      )
    {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $frame_ref->{flags} & PADDED ) {
        $pad = unpack( 'C', substr( $$buf_ref, $buf_offset ) );
        $offset += 1;
    }

    my $dblock_size = $length - $offset - $pad;
    if ( $dblock_size < 0 ) {
        tracer->error("Not enough space for data block\n");
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my $fcw = $con->fcw_recv( -$length );
    my $stream_fcw = $con->stream_fcw_recv( $frame_ref->{stream}, -$length );
    if ( $fcw < 0 || $stream_fcw < 0 ) {
        tracer->debug(
            "received data overflow flow control window: $fcw|$stream_fcw\n");
        $con->stream_error( $frame_ref->{stream}, FLOW_CONTROL_ERROR );
        return $length;
    }
    $con->fcw_update() if $fcw < $con->dec_setting(SETTINGS_MAX_FRAME_SIZE);
    $con->stream_fcw_update( $frame_ref->{stream} )
      if $stream_fcw < $con->dec_setting(SETTINGS_MAX_FRAME_SIZE)
      && !( $frame_ref->{flags} & END_STREAM );

    return $length unless $dblock_size;

    my $data = substr $$buf_ref, $buf_offset + $offset, $dblock_size;

    # Update stream data container
    $con->stream_data( $frame_ref->{stream}, $data );

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream_id, $data_ref ) = @_;

    return $$data_ref;
}

1;
