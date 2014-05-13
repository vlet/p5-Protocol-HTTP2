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
    my $self = {
        con            => undef,
        input          => '',
        active_streams => 0
    };

    if ( exists $opts{on_push} ) {
        my $cb = delete $opts{on_push};
        $opts{on_new_peer_stream} = sub {
            my $stream_id = shift;
            my $pp_headers;
            $self->active_streams(+1);

            $self->{con}->stream_cb(
                $stream_id,
                RESERVED,
                sub {
                    my $res =
                      $cb->( $self->{con}->stream_pp_headers($stream_id) );
                    if ( $res && ref $cb eq 'CODE' ) {
                        $self->{con}->stream_cb(
                            $stream_id,
                            CLOSED,
                            sub {
                                $res->(
                                    $self->{con}->stream_headers($stream_id),
                                    $self->{con}->stream_data($stream_id),
                                );
                                $self->active_streams(-1);
                            }
                        );
                    }
                    else {
                        $self->{con}
                          ->stream_error( $stream_id, REFUSED_STREAM );
                        $self->active_streams(-1);
                    }
                }
            );
        };
    }

    $self->{con} = Protocol::HTTP2::Connection->new( CLIENT, %opts );
    bless $self, $class;
}

sub active_streams {
    my $self = shift;
    my $add = shift || 0;
    $self->{active_streams} += $add;
    $self->{con}->finish unless $self->{active_streams} > 0;
}

my @must = (qw(:authority :method :path :scheme));

sub request {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing fields in request: @miss" if @miss;

    $self->active_streams(+1);

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
        if ( !$con->preface ) {
            $con->enqueue( $con->preface_encode,
                $con->frame_encode( SETTINGS, 0, 0, {} ) );
            $con->preface(1);
        }

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
            $self->active_streams(-1);
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
        $con->preface(1);
    }
    while ( $len = $con->frame_decode( \$self->{input}, $offset ) ) {
        tracer->debug("decoded frame at $offset, length $len\n");
        $offset += $len;
    }
    substr( $self->{input}, 0, $offset ) = '' if $offset;
}

1;
