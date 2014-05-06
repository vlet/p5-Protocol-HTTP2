package Protocol::HTTP2::Frame::Continuation;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my ( $pad_high, $pad_low ) = ( 0, 0 );
    my $offset    = 0;
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # CONTINUATION frames MUST be associated with a stream
        ( $frame_ref->{stream} == 0 ) ||

        # Error when PAD_HIGH is set, but PAD_LOW isn't
        (
               ( $frame_ref->{flags} & PAD_HIGH )
            && ( $frame_ref->{flags} & PAD_LOW ) == 0
        )

      )
    {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $frame_ref->{flags} & PAD_HIGH ) {
        $pad_high = unpack( 'C', substr( $$buf_ref, $buf_offset, 1 ) );
        $offset += 1;
    }

    if ( $frame_ref->{flags} & PAD_LOW ) {
        $pad_low = unpack( 'C', substr( $$buf_ref, $buf_offset + $offset, 1 ) );
        $offset += 1;
    }

    # Not enough space for header block
    my $hblock_size = $length - $offset - ( $pad_high << 8 ) - $pad_low;
    if ( $hblock_size <= 0 ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    $con->stream_header_block( $frame_ref->{stream},
        substr( $$buf_ref, $buf_offset + $offset, $hblock_size ) );

    # Stream header block complete
    $con->stream_headers_done( $frame_ref->{stream} )
      or return undef
      if $frame_ref->{flags} & END_HEADERS;

    return $length;

}

sub encode {
    my ( $con, $flags_ref, $stream, $data_ref ) = @_;
    return $$data_ref;
}

1;
