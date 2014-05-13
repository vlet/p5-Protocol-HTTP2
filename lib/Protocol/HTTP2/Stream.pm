package Protocol::HTTP2::Stream;
use strict;
use warnings;
use Hash::MultiValue;
use Protocol::HTTP2::Constants qw(:states :endpoints :settings :frame_types
  :limits);
use Protocol::HTTP2::HeaderCompression qw( headers_decode );
use Protocol::HTTP2::Trace qw(tracer);

# Streams related part of Protocol::HTTP2::Conntection

sub new_stream {
    my $self = shift;
    return undef if $self->goaway;

    $self->{last_stream} += 2
      if exists $self->{streams}->{ $self->{type} == CLIENT ? 1 : 2 };
    $self->{streams}->{ $self->{last_stream} } = {
        'state'    => IDLE,
        'fcw_recv' => $self->setting(SETTINGS_INITIAL_WINDOW_SIZE),
        'fcw_send' => $self->setting(SETTINGS_INITIAL_WINDOW_SIZE),
    };
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
    $self->{streams}->{$stream_id} = {
        'state'    => IDLE,
        'fcw_recv' => $self->setting(SETTINGS_INITIAL_WINDOW_SIZE),
        'fcw_send' => $self->setting(SETTINGS_INITIAL_WINDOW_SIZE),
    };
    $self->{on_new_peer_stream}->($stream_id)
      if exists $self->{on_new_peer_stream};

    return $self->{last_peer_stream};
}

sub stream {
    my ( $self, $stream_id ) = @_;
    return undef unless exists $self->{streams}->{$stream_id};

    $self->{streams}->{$stream_id};
}

# stream_state ( $self, $stream_id, $new_state?, $pending? )

sub stream_state {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        my ( $new_state, $pending ) = @_;

        if ($pending) {
            $self->stream_pending_state( $stream_id, $new_state );
        }
        else {
            $self->{on_change_state}->( $stream_id, $s->{state}, $new_state )
              if exists $self->{on_change_state};

            $s->{state} = $new_state;

            # Exec callbacks for new state
            if ( exists $s->{cb} && exists $s->{cb}->{ $s->{state} } ) {
                for my $cb ( @{ $s->{cb}->{ $s->{state} } } ) {
                    $cb->();
                }
            }

            # Cleanup
            if ( $new_state == CLOSED ) {
                $s = $self->{streams}->{$stream_id} = { state => CLOSED };
            }
        }
    }

    $s->{state};
}

sub stream_pending_state {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};
    $s->{pending_state} = shift if @_;
    $s->{pending_state};
}

sub stream_promised_sid {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};
    $s->{promised_sid} = shift if @_;
    $s->{promised_sid};
}

sub stream_cb {
    my ( $self, $stream_id, $state, $cb ) = @_;

    return undef unless exists $self->{streams}->{$stream_id};

    push @{ $self->{streams}->{$stream_id}->{cb}->{$state} }, $cb;
}

sub stream_data {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    $s->{data} .= shift if @_;

    $s->{data};
}

# Header Block -- The entire set of encoded header field representations
sub stream_header_block {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    $s->{header_block} .= shift if @_;

    $s->{header_block};
}

sub stream_headers {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    $self->{streams}->{$stream_id}->{headers} = shift if @_;
    $self->{streams}->{$stream_id}->{headers};
}

sub stream_pp_headers {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    $self->{streams}->{$stream_id}->{pp_headers};
}

sub stream_headers_done {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    my $res =
      headers_decode( $self, \$s->{header_block}, 0,
        length $s->{header_block} );

    tracer->debug("Headers done for stream $stream_id\n");

    return undef unless defined $res;

    # Clear header_block
    $s->{header_block} = '';

    my $rs = $self->decode_context->{reference_set};
    my $eh = $self->decode_context->{emitted_headers};

    # TODO: http2 -> http/1.1 headers conversion
    my $h = Hash::MultiValue->new(@$eh);
    for my $kv_str ( keys %$rs ) {
        my ( $key, $value ) = @{ $rs->{$kv_str} };
        next if grep { $_ eq $value } $h->get_all($key);
        $h->add( $key, $value );
    }

    if ( $s->{promised_sid} ) {
        $self->{streams}->{ $s->{promised_sid} }->{pp_headers} =
          [ $h->flatten ];
    }
    else {
        $s->{headers} = [ $h->flatten ];
    }

    # Clear emitted headers
    $self->decode_context->{emitted_headers} = [];

    return 1;
}

# RST_STREAM for stream errors
sub stream_error {
    my ( $self, $stream_id, $error ) = @_;
    $self->enqueue(
        $self->frame_encode( RST_STREAM, 0, $stream_id, $error, '' ) );
}

# Flow control windown of stream
sub stream_fcw_send {
    shift->_stream_fcw( 'send', @_ );
}

sub stream_fcw_recv {
    shift->_stream_fcw( 'recv', @_ );
}

sub _stream_fcw {
    my $self      = shift;
    my $dir       = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        $s->{ 'fcw_' . $dir } += shift;
        tracer->debug( "Stream $stream_id fcw_$dir now is "
              . $s->{ 'fcw_' . $dir }
              . "\n" );
    }
    $s->{ 'fcw_' . $dir };
}

sub stream_fcw_update {
    my ( $self, $stream_id ) = @_;

    # TODO: check size of data of stream  in memory
    tracer->debug("update fcw recv of stream $stream_id\n");
    $self->stream_fcw_recv( $stream_id, DEFAULT_INITIAL_WINDOW_SIZE );
    $self->enqueue(
        $self->frame_encode( WINDOW_UPDATE, 0, $stream_id,
            DEFAULT_INITIAL_WINDOW_SIZE
        )
    );
}

sub stream_blocked_data {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        $s->{blocked_data} .= shift;
        $self->enqueue( $self->frame_encode( BLOCKED, 0, $stream_id, '' ) )
          if $self->stream_fcw_send($stream_id) == 0;
        $self->enqueue( $self->frame_encode( BLOCKED, 0, 0, '' ) )
          if $self->fcw_send == 0;
    }
    $s->{blocked_data};
}

sub stream_send_blocked {
    my ( $self, $stream_id ) = @_;
    my $blocked_data = $self->stream_blocked_data($stream_id);
    return undef
      unless defined $blocked_data
      && length($blocked_data)
      && $self->stream_fcw_send($stream_id) != 0;

    $self->send_data( $stream_id, $blocked_data );
}

1;
