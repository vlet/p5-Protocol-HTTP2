package Protocol::HTTP2::Frame::Continuation;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors :settings);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # CONTINUATION frames MUST be associated with a stream
        $frame_ref->{stream} == 0
      )
    {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }
    if (
        # Headers compressed size already exceeded decompressed limit
        length( $con->stream_header_block( $frame_ref->{stream} ) ) + $length >
        $con->dec_setting(SETTINGS_MAX_HEADER_LIST_SIZE)
      )
    {
        $con->error(ENHANCE_YOUR_CALM);
        return undef;
    }

    $con->stream_header_block_add( $frame_ref->{stream},
        substr( $$buf_ref, $buf_offset, $length ) )
      or return undef;

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
