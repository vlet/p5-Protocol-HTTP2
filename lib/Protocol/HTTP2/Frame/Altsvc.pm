package Protocol::HTTP2::Frame::Altsvc;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    require 'Carp';
    Carp::croak("Altsvc frame decoder not implemented");
}

sub encode {
    require 'Carp';
    Carp::croak("Altsvc frame encoder not implemented");
}

1;
