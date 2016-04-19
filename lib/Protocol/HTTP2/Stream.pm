package Protocol::HTTP2::Stream;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:states :endpoints :settings :frame_types
  :limits :errors);
use Protocol::HTTP2::HeaderCompression qw( headers_decode );
use Protocol::HTTP2::Trace qw(tracer);

# Streams related part of Protocol::HTTP2::Conntection

# Autogen properties
{
    no strict 'refs';
    for my $prop (
        qw(promised_sid headers pp_headers header_block trailer
        trailer_headers length blocked_data weight end reset)
      )
    {
        *{ __PACKAGE__ . '::stream_' . $prop } = sub {
            return
                !exists $_[0]->{streams}->{ $_[1] } ? undef
              : @_ == 2 ? $_[0]->{streams}->{ $_[1] }->{$prop}
              :           ( $_[0]->{streams}->{ $_[1] }->{$prop} = $_[2] );
          }
    }
}

sub new_stream {
    my $self = shift;
    return undef if $self->goaway;

    $self->{last_stream} += 2
      if exists $self->{streams}->{ $self->{type} == CLIENT ? 1 : 2 };
    $self->{streams}->{ $self->{last_stream} } = {
        'state'      => IDLE,
        'weight'     => DEFAULT_WEIGHT,
        'stream_dep' => 0,
        'fcw_recv'   => $self->dec_setting(SETTINGS_INITIAL_WINDOW_SIZE),
        'fcw_send'   => $self->enc_setting(SETTINGS_INITIAL_WINDOW_SIZE),
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
        tracer->error("Peer send invalid stream id: $stream_id\n");
        $self->error(PROTOCOL_ERROR);
        return undef;
    }
    $self->{last_peer_stream} = $stream_id;
    if ( $self->dec_setting(SETTINGS_MAX_CONCURRENT_STREAMS) <=
        $self->{active_peer_streams} )
    {
        tracer->warning("SETTINGS_MAX_CONCURRENT_STREAMS exceeded\n");
        $self->stream_error( $stream_id, REFUSED_STREAM );
        return undef;
    }
    $self->{active_peer_streams}++;
    tracer->debug("Active streams: $self->{active_peer_streams}");
    $self->{streams}->{$stream_id} = {
        'state'      => IDLE,
        'weight'     => DEFAULT_WEIGHT,
        'stream_dep' => 0,
        'fcw_recv'   => $self->dec_setting(SETTINGS_INITIAL_WINDOW_SIZE),
        'fcw_send'   => $self->enc_setting(SETTINGS_INITIAL_WINDOW_SIZE),
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
                $self->{active_peer_streams}--
                  if $self->{active_peer_streams}
                  && ( ( $stream_id % 2 ) ^ ( $self->{type} == CLIENT ) );
                tracer->info(
                    "Active streams: $self->{active_peer_streams} $stream_id");
                for my $key ( keys %$s ) {
                    next if grep { $key eq $_ } (
                        qw(state weight stream_dep
                          fcw_recv fcw_send reset)
                    );
                    delete $s->{$key};
                }
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
    if (@_) {
        $s->{pending_state} = shift;
        $self->{pending_stream} =
          defined $s->{pending_state} ? $stream_id : undef;
    }
    $s->{pending_state};
}

sub stream_cb {
    my ( $self, $stream_id, $state, $cb ) = @_;

    return undef unless exists $self->{streams}->{$stream_id};

    push @{ $self->{streams}->{$stream_id}->{cb}->{$state} }, $cb;
}

sub stream_frame_cb {
    my ( $self, $stream_id, $frame, $cb ) = @_;

    return undef unless exists $self->{streams}->{$stream_id};

    push @{ $self->{streams}->{$stream_id}->{frame_cb}->{$frame} }, $cb;
}

sub stream_data {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {

        # Exec callbacks for data
        if ( exists $s->{frame_cb} && exists $s->{frame_cb}->{&DATA} ) {
            for my $cb ( @{ $s->{frame_cb}->{&DATA} } ) {
                $cb->( $_[0] );
            }
        }
        else {
            $s->{data} .= shift;
        }
    }

    $s->{data};
}

sub stream_headers_done {
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    my $res =
      headers_decode( $self, \$s->{header_block}, 0,
        length $s->{header_block}, $stream_id );

    tracer->debug("Headers done for stream $stream_id\n");

    return undef unless defined $res;

    # Clear header_block
    $s->{header_block} = '';

    my $eh          = $self->decode_context->{emitted_headers};
    my $is_response = $self->{type} == CLIENT && !$s->{promised_sid};
    my $is_trailer  = !!$self->stream_trailer($stream_id);

    return undef
      unless $self->validate_headers( $eh, $stream_id, $is_response );

    if ( $s->{promised_sid} ) {
        $self->{streams}->{ $s->{promised_sid} }->{pp_headers} = $eh;
    }
    elsif ($is_trailer) {
        $self->stream_trailer_headers( $stream_id, $eh );
    }
    else {
        $s->{headers} = $eh;
    }

    # Exec callbacks for headers
    if ( exists $s->{frame_cb} && exists $s->{frame_cb}->{&HEADERS} ) {
        for my $cb ( @{ $s->{frame_cb}->{&HEADERS} } ) {
            $cb->($eh);
        }
    }

    # Clear emitted headers
    $self->decode_context->{emitted_headers} = [];

    return 1;
}

sub validate_headers {
    my ( $self, $headers, $stream_id, $is_response ) = @_;
    my $pseudo_flag = 1;
    my %pseudo_hash = ();
    my @h           = $is_response ? (qw(:status)) : (
        qw(:method :scheme :authority
          :path)
    );

    # Trailer headers ?
    if ( my $t = $self->stream_trailer($stream_id) ) {
        for my $i ( 0 .. @$headers / 2 - 1 ) {
            my ( $h, $v ) = ( $headers->[ $i * 2 ], $headers->[ $i * 2 + 1 ] );
            if ( !exists $t->{$h} ) {
                tracer->warning(
                    "header <$h> doesn't listed in the trailer header");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return undef;
            }
        }
        return 1;
    }

    for my $i ( 0 .. @$headers / 2 - 1 ) {
        my ( $h, $v ) = ( $headers->[ $i * 2 ], $headers->[ $i * 2 + 1 ] );
        if ( $h =~ /^\:/ ) {
            if ( !$pseudo_flag ) {
                tracer->warning(
                    "pseudo-header <$h> appears after a regular header");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return undef;
            }
            elsif ( !grep { $_ eq $h } @h ) {
                tracer->warning("invalid pseudo-header <$h>");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return undef;
            }
            elsif ( exists $pseudo_hash{$h} ) {
                tracer->warning("repeated pseudo-header <$h>");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return undef;
            }

            $pseudo_hash{$h} = $v;
            next;
        }

        $pseudo_flag = 0 if $pseudo_flag;

        if ( $h eq 'connection' ) {
            tracer->warning("connection header is not valid in http/2");
            $self->stream_error( $stream_id, PROTOCOL_ERROR );
            return undef;
        }
        elsif ( $h eq 'te' && $v ne 'trailers' ) {
            tracer->warning("TE header can contain only value 'trailers'");
            $self->stream_error( $stream_id, PROTOCOL_ERROR );
            return undef;
        }
        elsif ( $h eq 'content-length' ) {
            $self->stream_length( $stream_id, $v );
        }
        elsif ( $h eq 'trailer' ) {
            my %th = map { $_ => 1 } split /\s*,\s*/, lc($v);
            if (
                grep { exists $th{$_} } (
                    qw(transfer-encoding content-length host authentication
                      cache-control expect max-forwards pragma range te
                      content-encoding content-type content-range trailer)
                )
              )
            {
                tracer->warning("trailer header contain forbidden headers");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return undef;
            }
            $self->stream_trailer( $stream_id, {%th} );
        }
    }

    for my $h (@h) {
        next if exists $pseudo_hash{$h};

        tracer->warning("missed mandatory pseudo-header $h");
        $self->stream_error( $stream_id, PROTOCOL_ERROR );
        return undef;
    }

    1;
}

# RST_STREAM for stream errors
sub stream_error {
    my ( $self, $stream_id, $error ) = @_;
    $self->enqueue( RST_STREAM, 0, $stream_id, $error );
}

# Flow control windown of stream
sub _stream_fcw {
    my $dir       = shift;
    my $self      = shift;
    my $stream_id = shift;
    return undef unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        $s->{$dir} += shift;
        tracer->debug( "Stream $stream_id $dir now is " . $s->{$dir} . "\n" );
    }
    $s->{$dir};
}

sub stream_fcw_send {
    _stream_fcw( 'fcw_send', @_ );
}

sub stream_fcw_recv {
    _stream_fcw( 'fcw_recv', @_ );
}

sub stream_fcw_update {
    my ( $self, $stream_id ) = @_;

    # TODO: check size of data of stream  in memory
    tracer->debug("update fcw recv of stream $stream_id\n");
    $self->stream_fcw_recv( $stream_id, DEFAULT_INITIAL_WINDOW_SIZE );
    $self->enqueue( WINDOW_UPDATE, 0, $stream_id, DEFAULT_INITIAL_WINDOW_SIZE );
}

sub stream_send_blocked {
    my ( $self, $stream_id ) = @_;
    my $s = $self->{streams}->{$stream_id} or return undef;

    if ( length( $s->{blocked_data} )
        && $self->stream_fcw_send($stream_id) != 0 )
    {
        $self->send_data($stream_id);
    }
}

sub stream_reprio {
    my ( $self, $stream_id, $exclusive, $stream_dep ) = @_;
    return undef
      unless exists $self->{streams}->{$stream_id}
      && ( $stream_dep == 0 || exists $self->{streams}->{$stream_dep} )
      && $stream_id != $stream_dep;
    my $s = $self->{streams};

    if ( $s->{$stream_id}->{stream_dep} != $stream_dep ) {

        # check if new stream_dep is stream child
        if ( $stream_dep != 0 ) {
            my $sid = $stream_dep;
            while ( $sid = $s->{$sid}->{stream_dep} ) {
                next unless $sid == $stream_id;

                # Child take my stream dep
                $s->{$stream_dep}->{stream_dep} =
                  $s->{$stream_id}->{stream_dep};
                last;
            }
        }

        # Set new stream dep
        $s->{$stream_id}->{stream_dep} = $stream_dep;
    }

    if ($exclusive) {

        # move all siblings to childs
        for my $sid ( keys %$s ) {
            next
              if $s->{$sid}->{stream_dep} != $stream_dep
              || $sid == $stream_id;

            $s->{$sid}->{stream_dep} = $stream_id;
        }
    }

    return 1;
}

1;
