package Protocol::HTTP2::Client;
use strict;
use warnings;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states :endpoints);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    my ( $class, %opts ) = @_;
    bless {
        con   => Protocol::HTTP2::Connection->new( SERVER, %opts ),
        input => '',
    }, $class;
}

my @must = (qw(:status));

sub response {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing fields in request: @miss" if @miss;

    my $con = $self->{con};

    my $stream_id = $con->new_stream;
    $con->send_headers(
        $stream_id,
        [
            ( map { $_ => $h{$_} } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ]
    );

    $con->send_data();
    return $self;

}

sub shutdown {
    shift->{con}->shutdown;
}

sub next_frame {
    my $self  = shift;
    my $frame = $self->{con}->dequeue;
    tracer->debug("send one frame to wire\n") if $frame;
    return $frame;
}

sub feed {
    my ( $self, $chunk ) = @_;
    $self->{input} .= $chunk;
    my $offset = 0;
    my $len;
    tracer->debug( "got " . length($chunk) . " bytes on a wire\n" );
    while ( $len = frame_decode( $self->{con}, \$self->{input}, $offset ) ) {
        tracer->debug("decoded frame at $offset, length $len\n");
        $offset += $len;
    }
    substr( $self->{input}, 0, $offset ) = '' if $offset;
}

1;
