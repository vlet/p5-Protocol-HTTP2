package Protocol::HTTP2::Connection;
use strict;
use warnings;
use Protocol::HTTP2::Constants
  qw(const_name :frame_types :errors :settings :flags :states
  :limits :endpoints);
use Protocol::HTTP2::HeaderCompression qw(headers_encode);
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::Stream;
use Protocol::HTTP2::Trace qw(tracer);

# Mixin
our @ISA = qw(Protocol::HTTP2::Frame Protocol::HTTP2::Stream);

sub new {
    my ( $class, $type, %opts ) = @_;
    my $self = bless {
        type => $type,

        # Settings of current connection
        settings => {
            &SETTINGS_HEADER_TABLE_SIZE      => DEFAULT_HEADER_TABLE_SIZE,
            &SETTINGS_ENABLE_PUSH            => DEFAULT_ENABLE_PUSH,
            &SETTINGS_MAX_CONCURRENT_STREAMS => DEFAULT_MAX_CONCURRENT_STREAMS,
            &SETTINGS_INITIAL_WINDOW_SIZE    => DEFAULT_INITIAL_WINDOW_SIZE,
        },

        streams => {},

        last_stream => $type == CLIENT ? 1 : 2,
        last_peer_stream => 0,

        encode_ctx => {

            # HPACK. Reference Set
            reference_set => {},

            # HPACK. Header Table
            header_table => [],

            # HPACK. Header Table size
            ht_size => 0,

            max_ht_size => DEFAULT_HEADER_TABLE_SIZE,

        },

        decode_ctx => {

            # HPACK. Reference Set
            reference_set => {},

            # HPACK. Header Table
            header_table => [],

            # HPACK. Header Table size
            ht_size => 0,

            max_ht_size => DEFAULT_HEADER_TABLE_SIZE,

            # HPACK. Emitted headers
            emitted_headers => [],

            # last frame
            frame => {},
        },

        # Current error
        error => 0,

        # Output frames queue
        queue => [],

        # Connection must be shutdown
        shutdown => 0,

        # issued GOAWAY: no new streams on this connection
        goaway => 0,

        # get preface
        preface => 0,
    }, $class;

    for (qw(on_change_state on_new_peer_stream on_error)) {
        $self->{$_} = $opts{$_} if exists $opts{$_};
    }

    $self->enqueue(
        $type == CLIENT
        ? ( $self->preface_encode, $self->frame_encode( SETTINGS, 0, 0, {} ) )
        : $self->frame_encode( SETTINGS, 0, 0,
            {
                &SETTINGS_MAX_CONCURRENT_STREAMS =>
                  DEFAULT_MAX_CONCURRENT_STREAMS
            }
        )
    );
    $self;
}

sub decode_context {
    shift->{decode_ctx};
}

sub encode_context {
    shift->{encode_ctx};
}

sub dequeue {
    my $self = shift;
    shift @{ $self->{queue} };
}

sub enqueue {
    my ( $self, @frames ) = @_;
    push @{ $self->{queue} }, @frames;
}

sub finish {
    my $self = shift;
    $self->enqueue(
        $self->frame_encode( GOAWAY, 0, 0,
            [ $self->{last_peer_stream}, $self->{error} ]
        )
    );
    $self->{shutdown} = 1;
}

sub shutdown {
    shift->{'shutdown'};
}

sub goaway {
    my $self = shift;
    $self->{goaway} = shift if @_;
    $self->{goaway};
}

sub preface {
    my $self = shift;
    $self->{preface} = shift if @_;
    $self->{preface};
}

sub state_machine {
    my ( $self, $act, $type, $flags, $stream_id ) = @_;

    my $s          = $self->{streams}->{$stream_id};
    my $prev_state = $s->{state};

    # Direction server->client
    my $srv2cln = ( $self->{type} == SERVER && $act eq 'send' )
      || ( $self->{type} == CLIENT && $act eq 'recv' );

    # Direction client->server
    my $cln2srv = ( $self->{type} == SERVER && $act eq 'recv' )
      || ( $self->{type} == CLIENT && $act eq 'send' );

    # State machine
    # IDLE
    if ( $prev_state == IDLE ) {
        if ( $type == HEADERS && $cln2srv ) {
            $self->stream_state( $stream_id,
                ( $flags & END_STREAM ) ? HALF_CLOSED : OPEN );
        }
        elsif ( $type == PUSH_PROMISE && $srv2cln ) {
            $self->stream_state( $stream_id, RESERVED );
        }
        else {
            tracer->error(
                sprintf "invalid frame type %s for current stream state %s",
                const_name( "frame_types", $type ),
                const_name( "states",      $prev_state )
            );
            $self->error(PROTOCOL_ERROR);
        }
    }

    # OPEN
    elsif ( $prev_state == OPEN ) {
        if (   ( $flags & END_STREAM )
            && ( $type == DATA || $type == HEADERS ) )
        {
            $self->stream_state( $stream_id, HALF_CLOSED );
        }
        elsif ( $type == RST_STREAM ) {
            $self->stream_state( $stream_id, CLOSED );
        }
    }

    # RESERVED (local/remote)
    elsif ( $prev_state == RESERVED ) {
        if ( $type == RST_STREAM ) {
            $self->stream_state( $stream_id, CLOSED );
        }
        elsif ( $type == HEADERS && $srv2cln ) {
            $self->stream_state( $stream_id,
                ( $flags & END_STREAM ) ? CLOSED : HALF_CLOSED );
        }
        elsif ( $type != PRIORITY && $cln2srv ) {
            tracer->error("invalid frame $type for state RESERVED");
            $self->error(PROTOCOL_ERROR);
        }
    }

    # HALF_CLOSED (local/remote)
    elsif ( $prev_state == HALF_CLOSED ) {
        if (   ( $type == RST_STREAM )
            || ( ( $flags & END_STREAM ) && $srv2cln ) )
        {
            $self->stream_state( $stream_id, CLOSED );
        }
        elsif (
            ( !grep { $type == $_ } ( CONTINUATION, WINDOW_UPDATE, PRIORITY ) )
            && $cln2srv )
        {
            tracer->error( sprintf "invalid frame %s for state HALF CLOSED\n",
                const_name( "frame_types", $type ) );
            $self->error(PROTOCOL_ERROR);
        }
    }

    # CLOSED
    elsif ( $prev_state == CLOSED ) {
        tracer->error("stream is closed");
        $self->error(STREAM_CLOSED);
    }
    else {
        tracer->error("oops!");
        $self->error(INTERNAL_ERROR);
    }
}

# TODO: move this to some other module
sub send {
    my ( $self, $stream_id, $headers, $data ) = @_;

    my ( $first, @rest ) = headers_encode( $self->encode_context, $headers );

    my $flags = defined $data ? 0 : END_STREAM;
    $flags |= END_HEADERS unless @rest;

    $self->enqueue(
        $self->frame_encode( HEADERS, $flags, $stream_id, $first ) );
    while (@rest) {
        my $hdr = shift @rest;
        my $flags = @rest ? 0 : END_HEADERS;
        $self->enqueue(
            $self->frame_encode( CONTINUATION, $flags, $stream_id, $hdr ) );
    }

    return unless defined $data;

    while ( length($data) > MAX_PAYLOAD_SIZE ) {
        $self->enqueue(
            $self->frame_encode( DATA, 0, $stream_id,
                substr( $data, 0, MAX_PAYLOAD_SIZE, '' )
            )
        );
    }
    $self->enqueue(
        $self->frame_encode( DATA, END_STREAM, $stream_id, $data ) );
}

sub error {
    my $self = shift;
    if (@_) {
        $self->{error} = shift;
        $self->{on_error}->( $self->{error} ) if exists $self->{on_error};
        $self->finish;
    }
    $self->{error};
}

sub setting {
    my ( $self, $setting ) = @_;
    return undef unless exists $self->{settings}->{$setting};
    $self->{settings}->{$setting} = shift if @_ > 1;
    return $self->{settings}->{$setting};
}

sub accept_settings {
    my $self = shift;
    $self->enqueue( $self->frame_encode( SETTINGS, ACK, 0, {} ) );
}

1;
