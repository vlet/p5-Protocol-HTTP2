package Protocol::HTTP2::Connection;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:frame_types :errors :settings :flags :states
  :limits);
use Protocol::HTTP2::HeaderCompression qw(headers_encode);
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::Trace qw(tracer);
use Carp;

sub new {
    my ( $class, $type ) = @_;
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

        last_stream => ( $type eq 'server' ) ? 2 : 1,
        last_peer_stream => 0,

        encode_ctx => {

            # HPACK. Reference Set
            reference_set => {},

            # HPACK. Header Table
            header_table => [],

            # HPACK. Header Table size
            ht_size => 0,

            max_ht_size => DEFAULT_HEADER_TABLE_SIZE,

            # HPACK. Emitted headers
            emitted_headers => [],
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

            frame => {},
        },

        # Current error
        error => 0,

        queue => $type eq 'client'
        ? [ preface_encode, frame_encode( SETTINGS, 0, 0, {} ) ]
        : [
            frame_encode( SETTINGS, 0, 0,
                { &SETTINGS_MAX_CONCURRENT_STREAMS => 100 }
            )
        ],

        shutdown => 0,
    }, $class;

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
    tracer->debug("dequeue\n");
    shift @{ $self->{queue} };
}

sub enqueue {
    my ( $self, $frame ) = @_;
    tracer->debug("enqueue frame\n");
    push @{ $self->{queue} }, $frame;
}

sub finish {
    my $self = shift;
    $self->enqueue(
        frame_encode( GOAWAY, 0, 0,
            [ $self->{last_peer_stream}, $self->{error} ]
        )
    );
    $self->{shutdown} = 1;
}

sub shutdown {
    shift->{'shutdown'};
}

sub new_stream {
    my $self = shift;
    $self->{last_stream} += 2 if keys %{ $self->{streams} };
    $self->{streams}->{ $self->{last_stream} } = { 'state' => IDLE };
    return $self->{last_stream};
}

sub stream {
    my ( $self, $stream_id ) = @_;
    return undef unless exists $self->{streams}->{$stream_id};

    $self->{streams}->{$stream_id};
}

sub stream_state {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        $s->{state} = shift;
        $s->{cb}->{ $s->{state} }->()
          if exists $s->{cb} && exists $s->{cb}->{ $s->{state} };
    }

    $s->{state};
}

sub stream_cb {
    my ( $self, $stream_id, $state, $cb ) = @_;

    return undef unless exists $self->{streams}->{$stream_id};

    $self->{streams}->{$stream_id}->{cb}->{$state} = $cb;
}

sub send_headers {
    my ( $self, $stream_id, $headers ) = @_;

    my $state = $self->stream_state($stream_id);
    if ( $state != IDLE ) {
        tracer->error("Can't send headers on non IDLE streams ($stream_id)\n");
        return undef;
    }

    my ( $first, @rest ) = headers_encode( $self->{encode_ctx}, $headers );

    my $flags = @rest ? END_STREAM : END_STREAM | END_HEADERS;
    $self->enqueue( frame_encode( HEADERS, $flags, $stream_id, $first ) );
    while (@rest) {
        my $hdr = shift @rest;
        my $flags = @rest ? 0 : END_HEADERS;
        $self->enqueue(
            frame_encode( CONTINUATION, $flags, $stream_id, $hdr ) );
    }
    $self->stream_state( $stream_id, HALF_CLOSED );
}

sub error {
    my $self = shift;
    $self->{error} = shift if @_;
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
    $self->enqueue( frame_encode( SETTINGS, ACK, 0, {} ) );
}

1;
