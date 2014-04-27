package Protocol::HTTP2::Server;
use strict;
use warnings;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states :endpoints);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    my ( $class, %opts ) = @_;
    my $con;

    if ( exists $opts{on_request} ) {
        my $cb = delete $opts{on_request};
        $opts{on_new_peer_stream} = sub {
            my $stream_id = shift;
            $con->stream_cb(
                $stream_id,
                HALF_CLOSED,
                sub {
                    $cb->(
                        $stream_id,
                        $con->stream_headers($stream_id),
                        $con->stream_data($stream_id),
                    );
                }
            );
          }
    }

    $con = Protocol::HTTP2::Connection->new( SERVER, %opts ),
      bless {
        con   => $con,
        input => '',
      }, $class;
}

my @must = (qw(:status));

sub response {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing headers in response: @miss" if @miss;

    my $con = $self->{con};

    $con->send(
        $h{stream_id},
        [
            ( map { $_ => $h{$_} } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ],
        exists $h{data} ? $h{data} : ()
    );

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
    my $con = $self->{con};
    tracer->debug( "got " . length($chunk) . " bytes on a wire\n" );
    if ( !$con->preface ) {
        return unless $len = $con->preface_decode( \$self->{input}, $offset );
        tracer->debug("got preface\n");
        $offset += $len;
        $con->preface(1);
    }

    while ( $len = $con->frame_decode( \$self->{input}, $offset ) ) {
        tracer->debug("decoded frame at $offset, length $len\n");
        $offset += $len;
    }
    substr( $self->{input}, 0, $offset ) = '' if $offset;
}

1;
