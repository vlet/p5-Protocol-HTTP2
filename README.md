# NAME

Protocol::HTTP2 - HTTP/2 protocol implementation (RFC 7540)

# SYNOPSIS

    use Protocol::HTTP2;

    # get protocol identification string for secure connections
    print Protocol::HTTP2::ident_tls;           # h2

    # get protocol identification string for non-secure connections
    print Protocol::HTTP2::ident_plain;         # h2c

# DESCRIPTION

Protocol::HTTP2 is HTTP/2 protocol implementation (RFC 7540) with stateful
decoders/encoders of HTTP/2 frames. You may use this module to implement your
own HTTP/2 client/server/intermediate on top of your favorite event loop over
plain or tls socket (see examples).

# STATUS

Current status - beta. Structures, module names and methods seems like stable.
I've started this project to understand internals of HTTP/2 and may be it will
never become production, but at least it works.

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

- - -- not implemeted
- ± -- incomplete
- + -- implemented (may even work)

# MODULES

## [Protocol::HTTP2::Client](https://metacpan.org/pod/Protocol::HTTP2::Client)

Client protocol decoder/encoder with constructor of requests

## [Protocol::HTTP2::Server](https://metacpan.org/pod/Protocol::HTTP2::Server)

Server protocol decoder/encoder with constructor of responses/pushes

## [Protocol::HTTP2::Connection](https://metacpan.org/pod/Protocol::HTTP2::Connection)

Main low level module for protocol logic and state processing. Connection
object is a mixin of [Protocol::HTTP2::Frame](https://metacpan.org/pod/Protocol::HTTP2::Frame) (frame encoding/decoding),
[Protocol::HTTP2::Stream](https://metacpan.org/pod/Protocol::HTTP2::Stream) (stream operations) and [Protocol::HTTP2::Upgrade](https://metacpan.org/pod/Protocol::HTTP2::Upgrade)
(HTTP/1.1 Upgrade support)

## [Protocol::HTTP2::HeaderCompression](https://metacpan.org/pod/Protocol::HTTP2::HeaderCompression)

Module implements HPACK - Header Compression for HTTP/2 (RFC 7541).
[https://tools.ietf.org/html/rfc7541](https://tools.ietf.org/html/rfc7541)

## [Protocol::HTTP2::Constants](https://metacpan.org/pod/Protocol::HTTP2::Constants)

Module contains all defined in HTTP/2 protocol constants and default values

## [Protocol::HTTP2::Trace](https://metacpan.org/pod/Protocol::HTTP2::Trace)

Module for debugging. You can setup HTTP2\_DEBUG environment variable to change
verbosity of the module (output to STDOUT). Default level is error.

    $ export HTTP2_DEBUG=debug
    $ perl ./http2_program

# SEE ALSO

[https://github.com/vlet/p5-Protocol-HTTP2/wiki](https://github.com/vlet/p5-Protocol-HTTP2/wiki) - Protocol::HTTP2 wiki

[http://http2.github.io/](http://http2.github.io/) - official HTTP/2 specification site

[http://daniel.haxx.se/http2/](http://daniel.haxx.se/http2/) - http2 explained

# LICENSE

Copyright (C) Vladimir Lettiev.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Vladimir Lettiev <thecrux@gmail.com>
