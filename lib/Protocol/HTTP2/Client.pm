package Protocol::HTTP2::Client;
use strict;
use warnings;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states :endpoints
  :errors);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    my ( $class, %opts ) = @_;
    my $con;
    if ( exists $opts{on_push} ) {
        my $cb = delete $opts{on_push};
        $opts{on_new_peer_stream} = sub {
            my $stream_id = shift;
            my $pp_headers;

            $con->stream_cb(
                $stream_id,
                RESERVED,
                sub {
                    my $res = $cb->( $con->stream_pp_headers($stream_id) );
                    if ( $res && ref $cb eq 'CODE' ) {
                        $con->stream_cb(
                            $stream_id,
                            CLOSED,
                            sub {
                                $res->(
                                    $con->stream_headers($stream_id),
                                    $con->stream_data($stream_id),
                                );
                            }
                        );
                    }
                    else {
                        $con->stream_error( $stream_id, REFUSED_STREAM );
                    }
                }
            );
        };
    }

    $con = Protocol::HTTP2::Connection->new( CLIENT, %opts );
    bless {
        con   => $con,
        input => '',
    }, $class;
}

my @must = (qw(:authority :method :path :scheme));

sub request {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing fields in request: @miss" if @miss;

    my $con = $self->{con};

    my $stream_id = $con->new_stream;

    if ( $con->upgrade && !exists $self->{sent_upgrade} ) {
        $con->enqueue(
            $con->upgrade_request(
                ( map { $_ => $h{$_} } @must ),
                headers => exists $h{headers} ? $h{headers} : []
            )
        );
        $self->{sent_upgrade} = 1;
        $con->stream_state( $stream_id, HALF_CLOSED );
    }
    else {

        $con->send_headers(
            $stream_id,
            [
                ( map { $_ => $h{$_} } @must ),
                exists $h{headers} ? @{ $h{headers} } : ()
            ],
            1
        );
    }

    $con->stream_cb(
        $stream_id,
        CLOSED,
        sub {
            $h{on_done}->(
                $con->stream_headers($stream_id),
                $con->stream_data($stream_id),
            );
            $con->finish();
        }
    ) if exists $h{on_done};

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
    if ( $con->upgrade ) {
        $len = $con->decode_upgrade_response( \$self->{input}, $offset );
        $con->shutdown(1) unless defined $len;
        return unless $len;
        $offset += $len;
        $con->upgrade(0);
        $con->enqueue( $con->preface_encode );
    }
    while ( $len = $con->frame_decode( \$self->{input}, $offset ) ) {
        tracer->debug("decoded frame at $offset, length $len\n");
        $offset += $len;
    }
    substr( $self->{input}, 0, $offset ) = '' if $offset;
}

1;
