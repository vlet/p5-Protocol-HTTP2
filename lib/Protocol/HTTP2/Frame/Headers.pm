package Protocol::HTTP2::Frame::Headers;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :states :limits);
use Protocol::HTTP2::Trace qw(tracer);

# 6.2 HEADERS
sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my ( $pad_high, $pad_low, $weight, $exclusive, $stream_dep ) = ( 0, 0 );
    my $offset    = 0;
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # HEADERS frames MUST be associated with a stream
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

    if ( $frame_ref->{flags} & PRIORITY_FLAG ) {
        ( $stream_dep, $weight ) =
          unpack( 'NC', substr( $$buf_ref, $buf_offset + $offset, 5 ) );
        $exclusive = $stream_dep >> 31;
        $stream_dep &= 0x7FFF_FFFF;
        $weight++;

        $con->stream_weight( $frame_ref->{stream}, $weight );
        $con->stream_reprio( $frame_ref->{stream}, $exclusive, $stream_dep, );

        $offset += 5;
    }

    # Not enough space for header block
    my $hblock_size = $length - $offset - ( $pad_high << 8 ) - $pad_low;
    if ( $hblock_size < 0 ) {
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
    my $res = '';

    if ( exists $data_ref->{padding} ) {
        if ( $data_ref->{padding} > 255 ) {
            $$flags_ref |= PAD_HIGH | PAD_LOW;
            $res .= pack 'n', $data_ref->{padding};
        }
        else {
            $$flags_ref |= PAD_LOW;
            $res .= pack 'C', $data_ref->{padding};
        }
    }

    if ( exists $data_ref->{stream_dep} || exists $data_ref->{weight} ) {
        $$flags_ref |= PRIORITY_FLAG;
        my $weight = ( $data_ref->{weight} || DEFAULT_WEIGHT ) - 1;
        my $stream_dep = $data_ref->{stream_dep} || 0;
        $stream_dep |= ( 1 << 31 ) if $data_ref->{exclusive};
        $res .= pack 'NC', $stream_dep, $weight;
    }

    return $res . ${ $data_ref->{hblock} };
}

1;
