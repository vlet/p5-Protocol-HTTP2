package Protocol::HTTP2::Stream;
use strict;
use warnings;
use Hash::MultiValue;
use Protocol::HTTP2::Constants qw(:states :endpoints);
use Protocol::HTTP2::Trace qw(tracer);

# Streams related part of Protocol::HTTP2::Conntection

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

1;
