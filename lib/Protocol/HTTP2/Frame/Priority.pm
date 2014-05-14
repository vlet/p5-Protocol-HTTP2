package Protocol::HTTP2::Frame::Priority;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    # Priority frames MUST be associated with a stream
    if ( $frame_ref->{stream} == 0 ) {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $length != 5 ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my ( $stream_dep, $weight ) =
      unpack( 'NC', substr( $$buf_ref, $buf_offset, 5 ) );
    my $exclusive = $stream_dep >> 31;
    $stream_dep &= 0x7FFF_FFFF;
    $weight++;

    $con->stream_weight( $frame_ref->{stream}, $weight );
    $con->stream_reprio( $frame_ref->{stream}, $exclusive, $stream_dep, );

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data_ref ) = @_;
    my $stream_dep = $data_ref->[0];
    my $weight     = $data_ref->[1] - 1;
    pack( 'NC', $stream_dep, $weight );
}

1;
