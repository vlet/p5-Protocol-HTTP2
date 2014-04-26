package Protocol::HTTP2::Frame::Push_promise;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    require Carp;
    Carp::croak("Push_promise frame decoder not implemented");
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    require Carp;
    Carp::croak("Push_promise frame encoder not implemented");
}

1;
