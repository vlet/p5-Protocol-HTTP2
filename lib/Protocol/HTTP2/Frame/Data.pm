package Protocol::HTTP2::Frame::Data;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :settings :limits);
use Protocol::HTTP2::Trace qw(tracer);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my ( $pad_high, $pad_low, $offset ) = ( 0, 0, 0 );
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # DATA frames MUST be associated with a stream
        ( $frame_ref->{stream} == 0 ) ||

        # Error when PAD_HIGH is set, but PAD_LOW isn't
        (
               ( $frame_ref->{flags} & PAD_HIGH )
            && ( $frame_ref->{flags} & PAD_LOW ) == 0
        )
        || (  !$con->setting(SETTINGS_COMPRESS_DATA)
            && $frame_ref->{flags} & COMPRESSED )

      )
    {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $frame_ref->{flags} & PAD_HIGH ) {
        $pad_high = unpack( 'C', substr( $$buf_ref, $buf_offset ) );
        $offset += 1;
    }

    if ( $frame_ref->{flags} & PAD_LOW ) {
        $pad_low = unpack( 'C', substr( $$buf_ref, $buf_offset + $offset ) );
        $offset += 1;
    }

    my $dblock_size = $length - $offset - ( $pad_high << 8 ) - $pad_low;
    if ( $dblock_size < 0 ) {
        tracer->error("Not enough space for data block\n");
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my $fcw = $con->fcw_recv( -$dblock_size );
    my $stream_fcw =
      $con->stream_fcw_recv( $frame_ref->{stream}, -$dblock_size );
    if ( $fcw < 0 || $stream_fcw < 0 ) {
        tracer->debug(
            "received data overflow flow control window: $fcw|$stream_fcw\n");
        $con->stream_error( $frame_ref->{stream}, FLOW_CONTROL_ERROR );
        return $length;
    }
    $con->fcw_update() if $fcw < MAX_PAYLOAD_SIZE;
    $con->stream_fcw_update( $frame_ref->{stream} )
      if $stream_fcw < MAX_PAYLOAD_SIZE
      && !( $frame_ref->{flags} & END_STREAM );

    return $length unless $dblock_size;

    my $data = substr $$buf_ref, $buf_offset + $offset, $dblock_size;

    if ( $frame_ref->{flags} & COMPRESSED ) {
        my $output;
        my $status = gunzip \$data => \$output;
        unless ($status) {
            tracer->error("gunzip failed: $GunzipError\n");
            $con->error(PROTOCOL_ERROR);
            return undef;
        }
        $data = $output;
    }

    # Update stream data container
    $con->stream_data( $frame_ref->{stream}, $data );

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream_id, $data_ref ) = @_;

    return $$data_ref;
}

1;
