package Protocol::HTTP2::Frame::Goaway;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(const_name :flags :errors);
use Protocol::HTTP2::Trace qw(tracer bin2hex);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    if ( $frame_ref->{stream} != 0 ) {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    my ( $last_stream_id, $error_code ) =
      unpack( 'N2', substr( $$buf_ref, $buf_offset, 8 ) );

    $last_stream_id &= 0x7FFF_FFFF;

    tracer->debug( "GOAWAY with error code "
          . const_name( 'errors', $error_code )
          . " last stream is $last_stream_id\n" );

    tracer->debug( "additional debug data: "
          . bin2hex( substr( $$buf_ref, $buf_offset + 8 ) )
          . "\n" )
      if $length - 8 > 0;

    $con->goaway(1);

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;

    $con->goaway(1);

    my $payload = pack( 'N2', @$data );
    tracer->debug( "\tGOAWAY: last stream = $data->[0], error = "
          . const_name( "errors", $data->[1] )
          . "\n" );
    $payload .= $data->[2] if @$data > 2;
    return $payload;
}

1;
