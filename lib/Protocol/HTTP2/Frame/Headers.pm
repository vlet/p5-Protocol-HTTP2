package Protocol::HTTP2::Frame::Headers;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :states);
use Protocol::HTTP2::HeaderCompression qw( headers_decode headers_encode );
use Protocol::HTTP2::Trace qw(tracer);

# 6.2 HEADERS
sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my ( $pad_high, $pad_low, $pg_id, $weight, $exclusive, $stream_dep ) =
      ( 0, 0 );
    my $offset    = 0;
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # HEADERS frames MUST be associated with a stream
        ( $frame_ref->{stream} == 0 ) ||

        # PRIORITY_GROUP and PRIORITY_DEPENDENCY can't be set both
        (
               ( $frame_ref->{flags} & PRIORITY_GROUP )
            && ( $frame_ref->{flags} & PRIORITY_DEPENDENCY )
        )
        ||

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

    if ( $frame_ref->{flags} & PRIORITY_GROUP ) {
        ( $pg_id, $weight ) =
          unpack( 'NC', substr( $$buf_ref, $buf_offset + $offset, 5 ) );
        $pg_id &= 0x7FFF_FFFF;
        $offset += 5;
    }

    if ( $frame_ref->{flags} & PRIORITY_DEPENDENCY ) {
        $stream_dep =
          unpack( 'N', substr( $$buf_ref, $buf_offset + $offset, 4 ) );
        $exclusive = $stream_dep & 0x8000_0000;
        $stream_dep &= 0x7FFF_FFFF;
        $offset += 4;
    }

    # Not enough space for header block
    my $hblock_size = $length - $offset - ( $pad_high << 8 ) - $pad_low;
    if ( $hblock_size <= 0 ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my $res =
      headers_decode( $con, $buf_ref, $buf_offset + $offset, $hblock_size );

    # Stream headers decoding complete
    $con->stream_headers_done( $frame_ref->{stream} )
      if $frame_ref->{flags} & END_HEADERS;

    return defined $res ? $length : undef;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    return $data;
}

1;
