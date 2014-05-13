package Protocol::HTTP2::Server;
use strict;
use warnings;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states :endpoints
  :settings :limits const_name);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        con   => undef,
        input => '',
    };

    if ( exists $opts{on_request} ) {
        $self->{cb} = delete $opts{on_request};
        $opts{on_new_peer_stream} = sub {
            my $stream_id = shift;
            $self->{con}->stream_cb(
                $stream_id,
                HALF_CLOSED,
                sub {
                    $self->{cb}->(
                        $stream_id,
                        $self->{con}->stream_headers($stream_id),
                        $self->{con}->stream_data($stream_id),
                    );
                }
            );
          }
    }

    $self->{con} = Protocol::HTTP2::Connection->new( SERVER, %opts );
    $self->{con}->enqueue(
        $self->{con}->frame_encode( SETTINGS, 0, 0,
            {
                &SETTINGS_MAX_CONCURRENT_STREAMS =>
                  DEFAULT_MAX_CONCURRENT_STREAMS
            }
        )
    ) unless $self->{con}->upgrade;

    bless $self, $class;
}

my @must = (qw(:status));

sub response {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing headers in response: @miss" if @miss;

    my $con = $self->{con};

    $con->send_headers(
        $h{stream_id},
        [
            ( map { $_ => $h{$_} } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ],
        exists $h{data} ? 0 : 1
    );
    $con->send_data( $h{stream_id}, $h{data} ) if exists $h{data};

    return $self;
}

my @must_pp = (qw(:authority :method :path :scheme));

sub push {
    my ( $self, %h ) = @_;
    my $con = $self->{con};
    my @miss = grep { !exists $h{$_} } @must_pp;
    croak "Missing headers in push promise: @miss" if @miss;
    croak "Can't push on my own stream. "
      . "Seems like a recursion in request callback."
      if $h{stream_id} % 2 == 0;

    my $promised_sid = $con->new_stream;
    $con->stream_promised_sid( $h{stream_id}, $promised_sid );

    my @headers = map { $_ => $h{$_} } @must_pp;

    $con->send_pp_headers( $h{stream_id}, $promised_sid, \@headers, );

    # send promised response after current stream is closed
    $con->stream_cb(
        $h{stream_id},
        CLOSED,
        sub {
            $self->{cb}->( $promised_sid, \@headers );
        }
    );

    return $self;
}

sub shutdown {
    shift->{con}->shutdown;
}

sub next_frame {
    my $self  = shift;
    my $frame = $self->{con}->dequeue;
    if ($frame) {
        my ( $length, $type, $flags, $stream_id ) =
          $self->{con}->frame_header_decode( \$frame, 0 );
        tracer->debug(
            sprintf "Send one frame to a wire:"
              . " type(%s), length(%i), flags(%08b), sid(%i)\n",
            const_name( 'frame_types', $type ), $length, $flags, $stream_id
        );
    }
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
        my @headers;
        my $len =
          $con->decode_upgrade_request( \$self->{input}, $offset, \@headers );
        $con->shutdown(1) unless defined $len;
        return unless $len;

        substr( $self->{input}, $offset, $len ) = '';

        $con->enqueue(
            $con->upgrade_response,
            $con->frame_encode( SETTINGS, 0, 0,
                {
                    &SETTINGS_MAX_CONCURRENT_STREAMS =>
                      DEFAULT_MAX_CONCURRENT_STREAMS
                }
              )

        );
        $con->upgrade(0);

        # The HTTP/1.1 request that is sent prior to upgrade is assigned stream
        # identifier 1 and is assigned default priority values (Section 5.3.5).
        # Stream 1 is implicitly half closed from the client toward the server,
        # since the request is completed as an HTTP/1.1 request.  After
        # commencing the HTTP/2 connection, stream 1 is used for the response.

        $con->new_peer_stream(1);
        $con->stream_headers( 1, \@headers );
        $con->stream_state( 1, HALF_CLOSED );
    }

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
