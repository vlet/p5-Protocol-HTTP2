package Protocol::HTTP2::Upgrade;
use strict;
use warnings;
use Protocol::HTTP2;
use Protocol::HTTP2::Constants qw(:frame_types :errors :states);
use Protocol::HTTP2::Trace qw(tracer);
use MIME::Base64 qw(encode_base64url decode_base64url);

#use re 'debug';
my $end_headers_re = qr/\G.+?\x0d?\x0a\x0d?\x0a/s;
my $header_re      = qr/\G[ \t]*(.+?)[ \t]*\:[ \t]*(.+?)[ \t]*\x0d?\x0a/;

sub upgrade_request {
    my ( $con, %h ) = @_;
    my $request = sprintf "%s %s HTTP/1.1\x0d\x0aHost: %s\x0d\x0a",
      $h{':method'}, $h{':path'},
      $h{':authority'};
    while ( my ( $h, $v ) = splice( @{ $h{headers} }, 0, 2 ) ) {
        next if grep { lc($h) eq $_ } (qw(connection upgrade http2-settings));
        $request .= $h . ': ' . $v . "\x0d\x0a";
    }
    $request .= join "\x0d\x0a",
      'Connection: Upgrade, HTTP2-Settings',
      'Upgrade: ' . Protocol::HTTP2::ident_plain,
      'HTTP2-Settings: '
      . encode_base64url( $con->frame_encode( SETTINGS, 0, 0, {} ) ),
      '', '';
}

sub upgrade_response {

    join "\x0d\x0a",
      "HTTP/1.1 101 Switching Protocols",
      "Connection: Upgrade",
      "Upgrade: " . Protocol::HTTP2::ident_plain,
      "", "";

}

sub decode_upgrade_request {
    my ( $con, $buf_ref, $buf_offset, $headers_ref ) = @_;

    pos($$buf_ref) = $buf_offset;

    # Search end of headers
    return 0 if $$buf_ref !~ /$end_headers_re/g;
    my $end_headers_pos = pos($$buf_ref) - $buf_offset;

    pos($$buf_ref) = $buf_offset;

    # Request
    return undef if $$buf_ref !~ m#\G(\w+) ([^ ]+) HTTP/1\.1\x0d?\x0a#g;
    my ( $method, $uri ) = ( $1, $2 );

    # TODO: remove after http2 -> http/1.1 headers conversion implemented
    push @$headers_ref, ":method", $method;
    push @$headers_ref, ":path",   $uri;

    my $success = 0;

    # Parse headers
    while ( $success != 0b111 && $$buf_ref =~ /$header_re/gc ) {
        my ( $header, $value ) = ( lc($1), $2 );

        if ( $header eq "connection" ) {
            my %h = map { $_ => 1 } split /\s*,\s*/, lc($value);
            $success |= 0b001
              if exists $h{'upgrade'} && exists $h{'http2-settings'};
        }
        elsif (
            $header eq "upgrade" && grep { $_ eq Protocol::HTTP2::ident_plain }
            split /\s*,\s*/,
            $value
          )
        {
            $success |= 0b010;
        }
        elsif ( $header eq "http2-settings"
            && defined $con->frame_decode( \decode_base64url($value), 0 ) )
        {
            $success |= 0b100;
        }
        else {
            push @$headers_ref, $header, $value;
        }
    }

    return undef unless $success == 0b111;

    # TODO: method POST also can contain data...

    return $end_headers_pos;

}

sub decode_upgrade_response {
    my ( $con, $buf_ref, $buf_offset ) = @_;

    pos($$buf_ref) = $buf_offset;

    # Search end of headers
    return 0 if $$buf_ref !~ /$end_headers_re/g;
    my $end_headers_pos = pos($$buf_ref) - $buf_offset;

    pos($$buf_ref) = $buf_offset;

    # Switch Protocols failed
    return undef if $$buf_ref !~ m#\GHTTP/1\.1 101 .+?\x0d?\x0a#g;

    my $success = 0;

    # Parse headers
    while ( $success != 0b11 && $$buf_ref =~ /$header_re/gc ) {
        my ( $header, $value ) = ( lc($1), $2 );

        if ( $header eq "connection" && lc($value) eq "upgrade" ) {
            $success |= 0b01;
        }
        elsif ( $header eq "upgrade" && $value eq Protocol::HTTP2::ident_plain )
        {
            $success |= 0b10;
        }
    }

    return undef unless $success == 0b11;

    return $end_headers_pos;
}

1;
