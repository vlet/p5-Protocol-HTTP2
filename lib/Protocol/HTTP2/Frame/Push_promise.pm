package Protocol::HTTP2::Frame::Push_promise;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :settings);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my ( $pad, $offset ) = ( 0, 0 );
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # PP frames MUST be associated with a stream
        $frame_ref->{stream} == 0

        # PP frames MUST be allowed
        || !$con->setting(SETTINGS_ENABLE_PUSH)
      )
    {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $frame_ref->{flags} & PADDED ) {
        $pad = unpack( 'C', substr( $$buf_ref, $buf_offset ) );
        $offset += 1;
    }

    my $promised_sid = unpack 'N', substr $$buf_ref, $buf_offset + $offset, 4;
    $promised_sid &= 0x7FFF_FFFF;
    $offset += 4;

    my $hblock_size = $length - $offset - $pad;
    if ( $hblock_size < 0 ) {
        tracer->error("Not enough space for header block\n");
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    $con->new_peer_stream($promised_sid) or return undef;
    $con->stream_promised_sid( $frame_ref->{stream}, $promised_sid );

    $con->stream_header_block( $frame_ref->{stream},
        substr( $$buf_ref, $buf_offset + $offset, $hblock_size ) );

    # PP header block complete
    $con->stream_headers_done( $frame_ref->{stream} )
      or return undef
      if $frame_ref->{flags} & END_HEADERS;

    return $length;

}

sub encode {
    my ( $con, $flags_ref, $stream_id, $data_ref ) = @_;
    my $promised_id = $data_ref->[0];
    my $hblock_ref  = $data_ref->[1];

    return pack( 'N', $promised_id ) . $$hblock_ref;
}

1;
