package Protocol::HTTP2::Frame::Rst_stream;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(const_name :flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    # RST_STREAM associated with stream
    if ( $frame_ref->{stream} == 0 ) {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    my $code = unpack( 'N', substr( $$buf_ref, $buf_offset, 4 ) );

    tracer->debug( "Receive reset stream with error code "
          . const_name( "errors", $code )
          . "\n" );

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    return pack 'N', $data;
}

1;
