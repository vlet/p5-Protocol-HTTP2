package Protocol::HTTP2::Frame::Settings;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    if ( $frame_ref->{stream} != 0 ) {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $frame_ref->{flags} & ACK ) {

        # just ack for our previous settings
        if ( $length != 0 ) {
            tracer->error(
                "ACK settings frame have non-zero ($length) payload\n");
            $con->error(FRAME_SIZE_ERROR);
            return undef;
        }

    }

    return 0 if $length == 0;

    if ( $length % 5 != 0 ) {
        tracer->error("Settings frame payload is broken (lenght $length)\n");
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my @settings = unpack( '(CN)*', substr( $$buf_ref, $buf_offset, $length ) );
    while ( my ( $key, $value ) = splice @settings, 0, 2 ) {
        tracer->debug("\tSettings $key = $value\n");
        if ( !defined $con->setting($key) ) {
            tracer->error("\tUnknown setting $key\n");
            $con->error(PROTOCOL_ERROR);
            return undef;
        }
        $con->setting( $key, $value );
    }

    $con->accept_settings();
    return $length;
}

sub encode {
    my ( $flags_ref, $stream, $data ) = @_;
    my $payload = '';
    for my $key ( sort keys %$data ) {
        tracer->debug("\tSettings $key = $data->{$key}\n");
        $payload .= pack( 'CN', $key, $data->{$key} );
    }
    return $payload;
}

1;
