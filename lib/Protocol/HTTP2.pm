package Protocol::HTTP2;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.01";

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

=head1 DESCRIPTION

Protocol::HTTP2 is HTTP/2 protocol (draft 12) implementation with stateful
decoders/encoders of HTTP/2 frames. You may use this module to implement your
own HTTP/2 client/server/intermediate on top of your favorite event loop over
plain or tls socket (see examples).

Current status - alpha. Structures, module names and methods may change vastly.
I've started this project to understand internals of HTTP/2 and may be it will
never become production or even finished.

=head1 STATUS

    | Spec                    | status  |
    | ----------------------- | ------- |
    | Negotiation             | direct  |
    | Preface                 |    +    |
    | Headers (de)compression |    +    |
    | Stream states           |    +    |
    | Flow control            |    -    |
    | Server push             |    -    |
    | Connect method          |    -    |


    | Frame           | encoder | decoder |
    | --------------- |:-------:|:-------:|
    | DATA            |    ~    |    +    |
    | HEADERS         |    +    |    +    |
    | PRIORITY        |    -    |    -    |
    | RST_STREAM      |    -    |    +    |
    | SETTINGS        |    +    |    +    |
    | PUSH_PROMISE    |    -    |    -    |
    | PING            |    -    |    -    |
    | GOAWAY          |    +    |    +    |
    | WINDOW_UPDATE   |    -    |    -    |
    | CONTINUATION    |    ~    |    +    |
    | ALTSVC          |    -    |    -    |
    | BLOCKED         |    -    |    ~    |


=over

=item - -- not implemeted

=item ~ -- incomplete

=item + -- implemented (may even work)

=back

=head1 SEE ALSO

L<http://http2.github.io/> - official HTTP/2 specification site

=head1 LICENSE

Copyright (C) Vladimir Lettiev.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Vladimir Lettiev E<lt>thecrux@gmail.com<gt>

=cut

