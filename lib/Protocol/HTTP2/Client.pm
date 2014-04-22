package Protocol::HTTP2::Client;
use strict;
use warnings;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        con   => Protocol::HTTP2::Connection->new('client'),
        input => '',
    };
    $self->{on_error} = $opts{on_error} if exists $opts{on_error};

    bless $self, $class;
}

my @must = (qw(:authority :method :path :scheme));

sub request {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing fields in request: @miss" if @miss;

    my $con = $self->{con};

    my $stream_id = $con->new_stream;
    $con->send_headers(
        $stream_id,
        [
            ( map { [ $_ => $h{$_} ] } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ]
    );

    $con->stream_cb(
        $stream_id,
        CLOSED,
        sub {
            $h{on_done}->(
                $con->stream($stream_id)->{headers},
                $con->stream($stream_id)->{data},
            );
            $con->finish();
        }
    ) if exists $h{on_done};

    return $self;
}

sub shutdown {
    shift->{con}->shutdown;
}

sub data {
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
    if ( !defined $len ) {
        $self->{on_error}->() if exists $self->{on_error};
    }
    else {
        substr( $self->{input}, 0, $offset ) = '';
    }
}

1;
