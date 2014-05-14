package Protocol::HTTP2::Connection;
use strict;
use warnings;
use Protocol::HTTP2::Constants
  qw(const_name :frame_types :errors :settings :flags :states
  :limits :endpoints);
use Protocol::HTTP2::HeaderCompression qw(headers_encode);
use Protocol::HTTP2::Frame;
use Protocol::HTTP2::Stream;
use Protocol::HTTP2::Upgrade;
use Protocol::HTTP2::Trace qw(tracer);

# Mixin
our @ISA =
  qw(Protocol::HTTP2::Frame Protocol::HTTP2::Stream Protocol::HTTP2::Upgrade);

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

        # perform upgrade
        upgrade => 0,

        # flow control
        fcw_send => DEFAULT_INITIAL_WINDOW_SIZE,
        fcw_recv => DEFAULT_INITIAL_WINDOW_SIZE,
    }, $class;

    for (qw(on_change_state on_new_peer_stream on_error upgrade)) {
        $self->{$_} = $opts{$_} if exists $opts{$_};
    }

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

sub process_state {
    my ( $self, $frame_ref ) = @_;
    my ( $length, $type, $flags, $stream_id ) =
      $self->frame_header_decode( $frame_ref, 0 );

    # Sended frame may change state of stream
    $self->state_machine( 'send', $type, $flags, $stream_id )
      if $type != SETTINGS && $type != GOAWAY && $stream_id != 0;
}

sub enqueue {
    my ( $self, @frames ) = @_;
    for (@frames) {
        push @{ $self->{queue} }, $_;
        $self->process_state( \$_ ) if !$self->upgrade && $self->preface;
    }
}

sub enqueue_first {
    my ( $self, @frames ) = @_;
    my $i = 0;
    for ( 0 .. $#{ $self->{queue} } ) {
        last
          if ( ( $self->frame_header_decode( \$self->{queue}->[$_], 0 ) )[1] !=
            CONTINUATION );
        $i++;
    }
    for (@frames) {
        splice @{ $self->{queue} }, $i++, 0, $_;
        $self->process_state( \$_ );
    }
}

sub finish {
    my $self = shift;
    $self->enqueue(
        $self->frame_encode( GOAWAY, 0, 0,
            [ $self->{last_peer_stream}, $self->{error} ]
        )
    ) unless $self->shutdown;
    $self->shutdown(1);
}

sub shutdown {
    my $self = shift;
    $self->{shutdown} = shift if @_;
    $self->{shutdown};
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

sub upgrade {
    my $self = shift;
    $self->{upgrade} = shift if @_;
    $self->{upgrade};
}

sub state_machine {
    my ( $self, $act, $type, $flags, $stream_id ) = @_;

    my $promised_sid = $self->stream_promised_sid($stream_id);

    my $prev_state = $self->{streams}->{ $promised_sid || $stream_id }->{state};

    # Direction server->client
    my $srv2cln = ( $self->{type} == SERVER && $act eq 'send' )
      || ( $self->{type} == CLIENT && $act eq 'recv' );

    # Direction client->server
    my $cln2srv = ( $self->{type} == SERVER && $act eq 'recv' )
      || ( $self->{type} == CLIENT && $act eq 'send' );

    # Do we expect CONTINUATION after this frame?
    my $pending = ( $type == HEADERS || $type == PUSH_PROMISE )
      && !( $flags & END_HEADERS );

    #tracer->debug(
    #    sprintf "\e[0;31mStream state: frame %s is %s%s on %s stream %i\e[m\n",
    #    const_name( "frame_types", $type ),
    #    $act,
    #    $pending ? "*" : "",
    #    const_name( "states", $prev_state ),
    #    $promised_sid || $stream_id,
    #    $stream_id,
    #);

    # Wait until all CONTINUATION frames arrive
    if ( my $ps = $self->stream_pending_state($stream_id) ) {
        if ( $type != CONTINUATION ) {
            tracer->error(
                sprintf "invalid frame type %s. Expected CONTINUATION frame\n",
                const_name( "frame_types", $type )
            );
            $self->error(PROTOCOL_ERROR);
        }
        elsif ( $flags & END_HEADERS ) {
            $self->stream_promised_sid( $stream_id, undef ) if $promised_sid;
            $self->stream_pending_state( $promised_sid || $stream_id, undef );
            $self->stream_state( $promised_sid || $stream_id, $ps );
        }
    }

    # State machine
    # IDLE
    elsif ( $prev_state == IDLE ) {
        if ( $type == HEADERS && $cln2srv ) {
            $self->stream_state( $stream_id,
                ( $flags & END_STREAM ) ? HALF_CLOSED : OPEN, $pending );
        }
        elsif ( $type == PUSH_PROMISE && $srv2cln ) {
            $self->stream_state( $promised_sid, RESERVED, $pending );
            $self->stream_promised_sid( $stream_id, undef )
              if $flags & END_HEADERS;
        }
        else {
            tracer->error(
                sprintf "invalid frame type %s for current stream state %s\n",
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
            $self->stream_state( $stream_id, HALF_CLOSED, $pending );
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
                ( $flags & END_STREAM ) ? CLOSED : HALF_CLOSED, $pending );
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
            $self->stream_state( $stream_id, CLOSED, $pending );
        }
        elsif ( ( !grep { $type == $_ } ( WINDOW_UPDATE, PRIORITY ) )
            && $cln2srv )
        {
            tracer->error( sprintf "invalid frame %s for state HALF CLOSED\n",
                const_name( "frame_types", $type ) );
            $self->error(PROTOCOL_ERROR);
        }
    }

    # CLOSED
    elsif ( $prev_state == CLOSED ) {
        if ( $type != WINDOW_UPDATE && $cln2srv ) {

            tracer->error("stream is closed\n");
            $self->error(STREAM_CLOSED);
        }
    }
    else {
        tracer->error("oops!\n");
        $self->error(INTERNAL_ERROR);
    }
}

# TODO: move this to some other module
sub send_headers {
    my ( $self, $stream_id, $headers, $end ) = @_;

    my $header_block = headers_encode( $self->encode_context, $headers );

    my $flags = $end ? END_STREAM : 0;
    $flags |= END_HEADERS if length($header_block) <= MAX_PAYLOAD_SIZE;

    $self->enqueue(
        $self->frame_encode( HEADERS, $flags, $stream_id,
            { hblock => \substr( $header_block, 0, MAX_PAYLOAD_SIZE, '' ) }
        )
    );
    while ( length($header_block) > 0 ) {
        my $flags = length($header_block) <= MAX_PAYLOAD_SIZE ? 0 : END_HEADERS;
        $self->enqueue(
            $self->frame_encode( CONTINUATION, $flags, $stream_id,
                \substr( $header_block, 0, MAX_PAYLOAD_SIZE, '' )
            )
        );
    }
}

sub send_pp_headers {
    my ( $self, $stream_id, $promised_id, $headers ) = @_;

    my $header_block = headers_encode( $self->encode_context, $headers );

    my $flags = length($header_block) <= MAX_PAYLOAD_SIZE ? END_HEADERS : 0;

    $self->enqueue(
        $self->frame_encode( PUSH_PROMISE,
            $flags,
            $stream_id,
            [
                $promised_id,
                \substr( $header_block, 0, MAX_PAYLOAD_SIZE - 4, '' )
            ]
        )
    );

    while ( length($header_block) > 0 ) {
        my $flags = length($header_block) <= MAX_PAYLOAD_SIZE ? 0 : END_HEADERS;
        $self->enqueue(
            $self->frame_encode( CONTINUATION, $flags, $stream_id,
                \substr( $header_block, 0, MAX_PAYLOAD_SIZE, '' )
            )
        );
    }
}

sub send_data {
    my ( $self, $stream_id, $data ) = @_;
    while ( ( my $l = length($data) ) > 0 ) {
        my $size = MAX_PAYLOAD_SIZE;
        for ( $l, $self->fcw_send, $self->stream_fcw_send($stream_id) ) {
            $size = $_ if $size > $_;
        }
        my $flags = $l == $size ? END_STREAM : 0;

        # Flow control
        if ( $size == 0 ) {
            $self->stream_blocked_data( $stream_id, $data );
            last;
        }
        $self->fcw_send( -$size );
        $self->stream_fcw_send( $stream_id, -$size );

        $self->enqueue(
            $self->frame_encode( DATA, $flags,
                $stream_id, \substr( $data, 0, $size, '' )
            )
        );
    }
}

sub send_blocked {
    my $self = shift;
    for my $stream_id ( keys %{ $self->{streams} } ) {
        $self->stream_send_blocked($stream_id);
    }
}

sub error {
    my $self = shift;
    if ( @_ && !$self->{shutdown} ) {
        $self->{error} = shift;
        $self->{on_error}->( $self->{error} ) if exists $self->{on_error};
        $self->finish;
    }
    $self->{error};
}

sub setting {
    my $self    = shift;
    my $setting = shift;
    return undef unless exists $self->{settings}->{$setting};
    $self->{settings}->{$setting} = shift if @_;
    return $self->{settings}->{$setting};
}

sub accept_settings {
    my $self = shift;
    $self->enqueue( $self->frame_encode( SETTINGS, ACK, 0, {} ) );
}

# Flow control windown of connection
sub fcw_send {
    shift->_fcw( 'send', @_ );
}

sub fcw_recv {
    shift->_fcw( 'recv', @_ );
}

sub _fcw {
    my $self = shift;
    my $dir  = shift;

    if (@_) {
        $self->{ 'fcw_' . $dir } += shift;
        tracer->debug( "fcw_$dir now is " . $self->{ 'fcw_' . $dir } . "\n" );
    }
    $self->{ 'fcw_' . $dir };
}

sub fcw_update {
    my $self = shift;

    # TODO: check size of data in memory
    tracer->debug("update fcw recv of connection\n");
    $self->fcw_recv(DEFAULT_INITIAL_WINDOW_SIZE);
    $self->enqueue(
        $self->frame_encode( WINDOW_UPDATE, 0, 0, DEFAULT_INITIAL_WINDOW_SIZE )
    );
}

sub ack_ping {
    my ( $self, $payload_ref ) = @_;
    $self->enqueue_first( $self->frame_encode( PING, ACK, 0, $payload_ref ) );
}

1;
