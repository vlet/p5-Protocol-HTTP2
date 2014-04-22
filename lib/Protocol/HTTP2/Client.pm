package Protocol::HTTP2::Client;
use strict;
use warnings;
use Protocol::HTTP2::Context;
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::HeaderCompression qw(headers_encode);
use Protocol::HTTP2::Constants qw(:frame_types :flags :preface);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    bless {
        decode_context => Protocol::HTTP2::Context->client,
        encode_context => Protocol::HTTP2::Context->client,
        frame_queue    => [],
        current_state  => 'NOT_CONNECTED',
      },
      shift;
}

my @must = (qw(:scheme :autority :path :method));

sub request {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing fields in request: @miss" if @miss;

    my $stream = $self->{encode_context}->new_stream;

    my ( $first, @rest ) = headers_encode(
        $self->{encode_context},
        [
            ( map { $_ => $h{$_} } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ]
    );

    my $flags = @rest ? 0 : END_SEGMENT | END_HEADERS;
    push @{ $self->{frame_queue} },
      frame_encode( HEADERS, $flags, $stream, $first );
    while (@rest) {
        my $hdr = shift @rest;
        my $flags = @rest ? 0 : END_SEGMENT | END_HEADERS;
        push @{ $self->{frame_queue} },
          frame_encode( CONTINUATION, $flags, $stream, $hdr );
    }
    return $self;
}

sub preface {
    my $self = shift;
    if ( $self->{current_state} eq 'NOT_CONNECTED' ) {
        return PREFACE;
    }
}

sub data {

}

sub feed {
    my $chunk = shift;

}

1;
