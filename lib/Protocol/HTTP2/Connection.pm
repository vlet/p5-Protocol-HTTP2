package Protocol::HTTP2::Connection;
use strict;
use warnings;
use Protocol::HTTP2::Constants
  qw(const_name :frame_types :errors :settings :flags :states
  :limits :endpoints);
use Protocol::HTTP2::HeaderCompression qw(headers_encode);
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::Trace qw(tracer);
use Carp;
use Hash::MultiValue;

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
    }, $class;

    for (qw(on_change_state on_error)) {
        $self->{$_} = $opts{$_} if exists $opts{$_};
    }

    $self->enqueue(
        $type == CLIENT
        ? ( preface_encode, frame_encode( SETTINGS, 0, 0, {} ) )
        : frame_encode( SETTINGS, 0, 0,
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
        frame_encode( GOAWAY, 0, 0,
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

sub new_stream {
    my $self = shift;
    return undef if $self->goaway;

    $self->{last_stream} += 2
      if exists $self->{streams}->{ $self->{type} == CLIENT ? 1 : 2 };
    $self->{streams}->{ $self->{last_stream} } = { 'state' => IDLE };
    return $self->{last_stream};
}

sub new_peer_stream {
    my $self      = shift;
    my $stream_id = shift;
    if (   $stream_id < $self->{last_peer_stream}
        || ( $stream_id % 2 ) == ( $self->{type} == CLIENT ) ? 1 : 0
        || $self->goaway )
    {
        return undef;
    }
    $self->{last_peer_stream} = $stream_id;
    $self->{streams}->{$stream_id} = { 'state' => IDLE };

    return $self->{last_peer_stream};
}

sub stream {
    my ( $self, $stream_id ) = @_;
    return undef unless exists $self->{streams}->{$stream_id};

    $self->{streams}->{$stream_id};
}

sub decode_state {
    my ( $self, $type, $flags, $stream_id ) = @_;

    my $s          = $self->{streams}->{$stream_id};
    my $prev_state = $s->{state};

    # State machine
    # IDLE
    if ( $prev_state == IDLE ) {
        if ( $type == HEADERS && $self->{type} == SERVER ) {
            $self->stream_state( $stream_id,
                ( $flags & END_STREAM ) ? HALF_CLOSED : OPEN );
        }
        elsif ( $type == PUSH_PROMISE && $self->{type} == CLIENT ) {
            $self->stream_state( $stream_id, RESERVED );
        }
        else {
            tracer->error(
                sprintf
                  "receive invalid frame type %s for current stream state %s",
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

    # RESERVED (local)
    elsif ( $prev_state == RESERVED && $self->{type} == SERVER ) {
        if ( $type == RST_STREAM ) {
            $self->stream_state( $stream_id, CLOSED );
        }
        elsif ( $type != PRIORITY ) {
            tracer->error("only RST_STREAM/PRIORITY frames accepted");
            $self->error(PROTOCOL_ERROR);
        }
    }

    # RESERVED (remote)
    elsif ( $prev_state == RESERVED && $self->{type} == CLIENT ) {
        if ( $type == RST_STREAM ) {
            $self->stream_state( $stream_id, CLOSED );
        }
        elsif ( $type == HEADERS ) {
            $self->stream_state( $stream_id,
                ( $flags & END_STREAM ) ? CLOSED : HALF_CLOSED );
        }
        else {
            tracer->error("only RST_STREAM/HEADERS frames accepted");
            $self->error(PROTOCOL_ERROR);
        }
    }

    # HALF_CLOSED (local)
    elsif ( $prev_state == HALF_CLOSED && $self->{type} == CLIENT ) {
        if ( $type == RST_STREAM || ( $flags & END_STREAM ) ) {
            $self->stream_state( $stream_id, CLOSED );
        }
    }

    # HALF_CLOSED (remote)
    elsif ( $prev_state == HALF_CLOSED && $self->{type} == SERVER ) {
        if ( $type != CONTINUATION ) {
            tracer->error("only CONTINUATION frames accepted");
            $self->error(STREAM_CLOSED);
        }
    }

    # CLOSED
    elsif ( $prev_state == CLOSED ) {
        if ( !grep { $type == $_ } ( WINDOW_UPDATE, PRIORITY, RST_STREAM ) ) {
            tracer->error("stream is closed");
            $self->error(STREAM_CLOSED);
        }
    }
    else {
        tracer->error("oops!");
        $self->error(INTERNAL_ERROR);
    }
}

sub stream_state {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        my $new_state = shift;

        $self->{on_change_state}->( $stream_id, $s->{state}, $new_state )
          if exists $self->{on_change_state};

        $s->{state} = $new_state;

        # Exec callbacks for new state
        $s->{cb}->{ $s->{state} }->()
          if exists $s->{cb} && exists $s->{cb}->{ $s->{state} };

        # Cleanup
        if ( $new_state == CLOSED ) {
            $s = $self->{streams}->{$stream_id} = { state => CLOSED };
        }
    }

    $s->{state};
}

sub stream_cb {
    my ( $self, $stream_id, $state, $cb ) = @_;

    return undef unless exists $self->{streams}->{$stream_id};

    $self->{streams}->{$stream_id}->{cb}->{$state} = $cb;
}

sub stream_data {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    $s->{data} .= shift if @_;

    $s->{data};
}

sub stream_headers {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    $self->{streams}->{$stream_id}->{headers};
}

# TODO: move this to some other module
sub send_headers {
    my ( $self, $stream_id, $headers ) = @_;

    my $state = $self->stream_state($stream_id);
    if ( $state != IDLE ) {
        tracer->error("Can't send headers on non IDLE streams ($stream_id)\n");
        return undef;
    }

    my ( $first, @rest ) = headers_encode( $self->encode_context, $headers );

    my $flags = @rest ? END_STREAM : END_STREAM | END_HEADERS;
    $self->enqueue( frame_encode( HEADERS, $flags, $stream_id, $first ) );
    while (@rest) {
        my $hdr = shift @rest;
        my $flags = @rest ? 0 : END_HEADERS;
        $self->enqueue(
            frame_encode( CONTINUATION, $flags, $stream_id, $hdr ) );
    }

    # TODO: this is work of encode_state()
    $self->stream_state( $stream_id, HALF_CLOSED );
}

sub stream_headers_done {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};
    tracer->debug("Headers done for stream $stream_id\n");

    my $rs = $self->decode_context->{reference_set};
    my $eh = $self->decode_context->{emitted_headers};

    my $h = Hash::MultiValue->new(@$eh);
    for my $kv_str ( keys %$rs ) {
        my ( $key, $value ) = @{ $rs->{$kv_str} };
        next if grep { $_ eq $value } $h->get_all($key);
        $h->add( $key, $value );
    }
    $s->{headers} = [ $h->flatten ];

    # Clear emitted headers;
    $self->decode_context->{emitted_headers} = [];
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
    $self->enqueue( frame_encode( SETTINGS, ACK, 0, {} ) );
}

1;
