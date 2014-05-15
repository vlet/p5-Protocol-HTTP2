package Protocol::HTTP2;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.07";

our $draft = "12";

sub ident_plain {
    'h2c-' . $draft;
}

sub ident_tls {
    'h2-' . $draft;
}

1;
__END__

=encoding utf-8

=head1 NAME

Protocol::HTTP2 - HTTP/2 protocol (draft 12) implementation

=head1 SYNOPSIS

    use Protocol::HTTP2;

    # get current draft version
    print $Protocol::HTTP2::draft;      # 12

    # get protocol identification string for secure connections
    print Protocol::HTTP2::ident_tls;   # h2-12

    # get protocol identification string for non-secure connections
    print Protocol::HTTP2::ident_plain; # h2c-12

=head1 DESCRIPTION

Protocol::HTTP2 is HTTP/2 protocol (draft 12) implementation with stateful
decoders/encoders of HTTP/2 frames. You may use this module to implement your
own HTTP/2 client/server/intermediate on top of your favorite event loop over
plain or tls socket (see examples).

=head1 STATUS

Current status - alpha. Structures, module names and methods may change vastly.
I've started this project to understand internals of HTTP/2 and may be it will
never become production or even finished.

    | Spec                    |      status     |
    | ----------------------- | --------------- |
    | Negotiation             |   ALPN, NPN,    |
    |                         | Upgrade, direct |
    | Preface                 |        +        |
    | Headers (de)compression |        +        |
    | Stream states           |        +        |
    | Flow control            |        ±        |
    | Stream priority         |        ±        |
    | Server push             |        +        |
    | Alternative services    |        -        |
    | Connect method          |        -        |


    | Frame           | encoder | decoder |
    | --------------- |:-------:|:-------:|
    | DATA            |    ±    |    +    |
    | HEADERS         |    +    |    +    |
    | PRIORITY        |    +    |    +    |
    | RST_STREAM      |    +    |    +    |
    | SETTINGS        |    +    |    +    |
    | PUSH_PROMISE    |    +    |    +    |
    | PING            |    +    |    +    |
    | GOAWAY          |    +    |    +    |
    | WINDOW_UPDATE   |    +    |    +    |
    | CONTINUATION    |    ±    |    +    |
    | ALTSVC          |    +    |    +    |
    | BLOCKED         |    +    |    ±    |


=over

=item - -- not implemeted

=item ± -- incomplete

=item + -- implemented (may even work)

=back

=head1 MODULES

=head2 L<Protocol::HTTP2::Client>

Client protocol decoder/encoder with constructor of requests

=head2 L<Protocol::HTTP2::Server>

Server protocol decoder/encoder with constructor of responses/pushes

=head2 L<Protocol::HTTP2::Connection>

Main low level module for protocol logic and state processing. Connection
object is a mixin of L<Protocol::HTTP2::Frame> (frame encoding/decoding),
L<Protocol::HTTP2::Stream> (stream operations) and L<Protocol::HTTP2::Upgrade>
(HTTP/1.1 Upgrade support)

=head2 L<Protocol::HTTP2::HeaderCompression>

Module implements HPACK (draft 07) - Header Compression for HTTP/2.
L<http://tools.ietf.org/html/draft-ietf-httpbis-header-compression-07>

=head2 L<Protocol::HTTP2::Constants>

Module contain all defined in HTTP/2 protocol constants and default values

=head2 L<Protocol::HTTP2::Trace>

Module for debugging. (Ab)used Log::Dispatch internally, may be removed soon.

=head1 SEE ALSO

L<http://http2.github.io/> - official HTTP/2 specification site
L<http://daniel.haxx.se/http2/> - http2 explained

=head1 LICENSE

Copyright (C) Vladimir Lettiev.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Vladimir Lettiev E<lt>thecrux@gmail.comE<gt>

=cut

