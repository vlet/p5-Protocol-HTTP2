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

# Default settings
my %default_settings = (
    &SETTINGS_HEADER_TABLE_SIZE      => DEFAULT_HEADER_TABLE_SIZE,
    &SETTINGS_ENABLE_PUSH            => DEFAULT_ENABLE_PUSH,
    &SETTINGS_MAX_CONCURRENT_STREAMS => DEFAULT_MAX_CONCURRENT_STREAMS,
    &SETTINGS_INITIAL_WINDOW_SIZE    => DEFAULT_INITIAL_WINDOW_SIZE,
    &SETTINGS_MAX_FRAME_SIZE         => DEFAULT_MAX_FRAME_SIZE,
    &SETTINGS_MAX_HEADER_LIST_SIZE   => DEFAULT_MAX_HEADER_LIST_SIZE,
);

sub new {
    my ( $class, $type, %opts ) = @_;
    my $self = bless {
        type => $type,

        streams => {},

        last_stream => $type == CLIENT ? 1 : 2,
        last_peer_stream    => 0,
        active_peer_streams => 0,

        encode_ctx => {

            # HPACK. Header Table
            header_table => [],

            # HPACK. Header Table size
            ht_size     => 0,
            max_ht_size => DEFAULT_HEADER_TABLE_SIZE,

            settings => {%default_settings},

        },

        decode_ctx => {

            # HPACK. Header Table
            header_table => [],

            # HPACK. Header Table size
            ht_size     => 0,
            max_ht_size => DEFAULT_HEADER_TABLE_SIZE,

            # HPACK. Emitted headers
            emitted_headers => [],

            # last frame
            frame => {},

            settings => {%default_settings},
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

        # stream where expected CONTINUATION frames
        pending_stream => undef,

    }, $class;

    for (qw(on_change_state on_new_peer_stream on_error upgrade)) {
        $self->{$_} = $opts{$_} if exists $opts{$_};
    }

    if ( exists $opts{settings} ) {
        for ( keys %{ $opts{settings} } ) {
            $self->{decode_ctx}->{settings}->{$_} = $opts{settings}{$_};
        }
    }

    # Sync decode context max_ht_size
    $self->{decode_ctx}->{max_ht_size} =
      $self->{decode_ctx}->{settings}->{&SETTINGS_HEADER_TABLE_SIZE};

    $self;
}

sub decode_context {
    shift->{decode_ctx};
}

sub encode_context {
    shift->{encode_ctx};
}

sub pending_stream {
    shift->{pending_stream};
}

sub dequeue {
    my $self = shift;
    shift @{ $self->{queue} };
}

sub enqueue_raw {
    my $self = shift;
    push @{ $self->{queue} }, @_;
}

sub enqueue {
    my $self = shift;
    while ( my ( $type, $flags, $stream_id, $data_ref ) = splice( @_, 0, 4 ) ) {
        push @{ $self->{queue} },
          $self->frame_encode( $type, $flags, $stream_id, $data_ref );
        $self->state_machine( 'send', $type, $flags, $stream_id );
    }
}

sub enqueue_first {
    my $self = shift;
    my $i    = 0;
    for ( 0 .. $#{ $self->{queue} } ) {
        my $type =
          ( $self->frame_header_decode( \$self->{queue}->[$_], 0 ) )[1];
        last if $type != CONTINUATION && $type != PING;
        $i++;
    }
    while ( my ( $type, $flags, $stream_id, $data_ref ) = splice( @_, 0, 4 ) ) {
        splice @{ $self->{queue} }, $i++, 0,
          $self->frame_encode( $type, $flags, $stream_id, $data_ref );
        $self->state_machine( 'send', $type, $flags, $stream_id );
    }
}

sub finish {
    my $self = shift;
    $self->enqueue( GOAWAY, 0, 0,
        [ $self->{last_peer_stream}, $self->{error} ] )
      unless $self->shutdown;
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

    return
         if $stream_id == 0
      || $type == SETTINGS
      || $type == GOAWAY
      || $self->upgrade
      || !$self->preface;

    my $promised_sid = $self->stream_promised_sid($stream_id);

    my $prev_state = $self->{streams}->{ $promised_sid || $stream_id }->{state};

    # REFUSED_STREAM error
    return if !defined $prev_state && $type == RST_STREAM && $act eq 'send';

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

    # Unexpected CONTINUATION frame
    elsif ( $type == CONTINUATION ) {
        tracer->error("Unexpected CONTINUATION frame\n");
        $self->error(PROTOCOL_ERROR);
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

        # first frame in stream is invalid, so state is yet IDLE
        elsif ( $type == RST_STREAM && $act eq 'send' ) {
            tracer->notice('send RST_STREAM on IDLE state. possible bug?');
            $self->stream_state( $stream_id, CLOSED );
        }
        elsif ( $type != PRIORITY ) {
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
        elsif ($type == HEADERS
            && !$pending
            && $self->stream_trailer($stream_id) )
        {
            tracer->error("expected END_STREAM flag for trailer HEADERS frame");
            $self->error(PROTOCOL_ERROR);
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
        if ( $type != PRIORITY && ( $type != WINDOW_UPDATE && $cln2srv ) ) {

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
    my $max_size = $self->enc_setting(SETTINGS_MAX_FRAME_SIZE);

    my $header_block = headers_encode( $self->encode_context, $headers );

    my $flags = $end ? END_STREAM : 0;
    $flags |= END_HEADERS if length($header_block) <= $max_size;

    $self->enqueue( HEADERS, $flags, $stream_id,
        { hblock => \substr( $header_block, 0, $max_size, '' ) } );
    while ( length($header_block) > 0 ) {
        my $flags = length($header_block) <= $max_size ? 0 : END_HEADERS;
        $self->enqueue( CONTINUATION, $flags,
            $stream_id, \substr( $header_block, 0, $max_size, '' ) );
    }
}

sub send_pp_headers {
    my ( $self, $stream_id, $promised_id, $headers ) = @_;
    my $max_size = $self->enc_setting(SETTINGS_MAX_FRAME_SIZE);

    my $header_block = headers_encode( $self->encode_context, $headers );

    my $flags = length($header_block) <= $max_size ? END_HEADERS : 0;

    $self->enqueue( PUSH_PROMISE, $flags, $stream_id,
        [ $promised_id, \substr( $header_block, 0, $max_size - 4, '' ) ] );

    while ( length($header_block) > 0 ) {
        my $flags = length($header_block) <= $max_size ? 0 : END_HEADERS;
        $self->enqueue( CONTINUATION, $flags,
            $stream_id, \substr( $header_block, 0, $max_size, '' ) );
    }
}

sub send_data {
    my ( $self, $stream_id, $chunk, $end ) = @_;
    my $data = $self->stream_blocked_data($stream_id);
    $data .= defined $chunk ? $chunk : '';
    $self->stream_end( $stream_id, $end ) if defined $end;
    $end = $self->stream_end($stream_id);

    while (1) {
        my $l    = length($data);
        my $size = $self->enc_setting(SETTINGS_MAX_FRAME_SIZE);
        for ( $l, $self->fcw_send, $self->stream_fcw_send($stream_id) ) {
            $size = $_ if $size > $_;
        }

        # Flow control
        if ( $l != 0 && $size <= 0 ) {
            $self->stream_blocked_data( $stream_id, $data );
            last;
        }
        $self->fcw_send( -$size );
        $self->stream_fcw_send( $stream_id, -$size );

        $self->enqueue(
            DATA, $end && $l == $size ? END_STREAM : 0,
            $stream_id, \substr( $data, 0, $size, '' )
        );
        last if $l == $size;
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
    require Carp;
    Carp::confess("setting is deprecated\n");
}

sub _setting {
    my ( $ctx, $self, $setting ) = @_;
    my $s = $self->{$ctx}->{settings};
    return undef unless exists $s->{$setting};
    $s->{$setting} = pop if @_ > 3;
    $s->{$setting};
}

sub enc_setting {
    _setting( 'encode_ctx', @_ );
}

sub dec_setting {
    _setting( 'decode_ctx', @_ );
}

sub accept_settings {
    my $self = shift;
    $self->enqueue( SETTINGS, ACK, 0, {} );
}

# Flow control windown of connection
sub _fcw {
    my $dir  = shift;
    my $self = shift;

    if (@_) {
        $self->{$dir} += shift;
        tracer->debug( "$dir now is " . $self->{$dir} . "\n" );
    }
    $self->{$dir};
}

sub fcw_send {
    _fcw( 'fcw_send', @_ );
}

sub fcw_recv {
    _fcw( 'fcw_recv', @_ );
}

sub fcw_update {
    my $self = shift;

    # TODO: check size of data in memory
    tracer->debug("update fcw recv of connection\n");
    $self->fcw_recv(DEFAULT_INITIAL_WINDOW_SIZE);
    $self->enqueue( WINDOW_UPDATE, 0, 0, DEFAULT_INITIAL_WINDOW_SIZE );
}

sub fcw_initial_change {
    my ( $self, $size ) = @_;
    my $prev_size = $self->enc_setting(SETTINGS_INITIAL_WINDOW_SIZE);
    my $diff      = $size - $prev_size;
    tracer->debug(
        "Change flow control window on not closed streams with diff $diff\n");
    for my $stream_id ( keys %{ $self->{streams} } ) {
        next if $self->stream_state($stream_id) == CLOSED;
        $self->stream_fcw_send( $stream_id, $diff );
    }
}

sub ack_ping {
    my ( $self, $payload_ref ) = @_;
    $self->enqueue_first( PING, ACK, 0, $payload_ref );
}

sub send_ping {
    my ( $self, $payload ) = @_;
    if ( !defined $payload ) {
        $payload = pack "C*", map { rand(256) } 1 .. PING_PAYLOAD_SIZE;
    }
    elsif ( length($payload) != PING_PAYLOAD_SIZE ) {
        $payload = sprintf "%*.*s",
          -PING_PAYLOAD_SIZE(), PING_PAYLOAD_SIZE, $payload;
    }
    $self->enqueue( PING, 0, 0, \$payload );
}

1;
