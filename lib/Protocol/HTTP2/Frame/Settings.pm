package Protocol::HTTP2::Frame::Settings;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(const_name :flags :errors);
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

    if ( $length % 6 != 0 ) {
        tracer->error("Settings frame payload is broken (lenght $length)\n");
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my @settings = unpack( '(SN)*', substr( $$buf_ref, $buf_offset, $length ) );
    while ( my ( $key, $value ) = splice @settings, 0, 2 ) {
        if ( !defined $con->setting($key) ) {
            tracer->debug("\tUnknown setting $key\n");

            # ignore unknown setting
            next;
        }
        else {
            tracer->debug( "\tSettings "
                  . const_name( "settings", $key )
                  . " = $value\n" );
        }
        $con->setting( $key, $value );
    }

    $con->accept_settings();
    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    my $payload = '';
    for my $key ( sort keys %$data ) {
        tracer->debug( "\tSettings "
              . const_name( "settings", $key )
              . " = $data->{$key}\n" );
        $payload .= pack( 'SN', $key, $data->{$key} );
    }
    return $payload;
}

1;
