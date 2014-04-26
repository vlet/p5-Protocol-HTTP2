package Protocol::HTTP2::Frame::Ping;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    require Carp;
    Carp::croak("Ping frame decoder not implemented");
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    require Carp;
    Carp::croak("Ping frame encoder not implemented");
}

1;
