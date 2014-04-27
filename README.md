# NAME

Protocol::HTTP2 - HTTP/2 protocol (draft 12) implementation

# SYNOPSIS

    use Protocol::HTTP2;

# DESCRIPTION

Protocol::HTTP2 is HTTP/2 protocol (draft 12) implementation with stateful
decoders/encoders of HTTP/2 frames. You may use this module to implement your
own HTTP/2 client/server/intermediate on top of your favorite event loop over
plain or tls socket (see examples).

Current status - alpha. Structures, module names and methods may change vastly.
I've started this project to understand internals of HTTP/2 and may be it will
never become production or even finished.

# STATUS

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
    | CONTINUATION    |    ~    |    -    |
    | ALTSVC          |    -    |    -    |
    | BLOCKED         |    -    |    ~    |



- \- -- not implemeted
- ~ -- incomplete
- \+ -- implemented (may even work)

# SEE ALSO

[http://http2.github.io/](http://http2.github.io/) - official HTTP/2 specification site

# LICENSE

Copyright (C) Vladimir Lettiev.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Vladimir Lettiev <thecrux@gmail.com<gt>
