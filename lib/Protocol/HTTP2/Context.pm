package Protocol::HTTP2::Context;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:frame_types :errors :settings);
use Carp;

sub client {
    _new( shift, 'client' );
}

sub server {
    _new( shift, 'server' );
}

sub _new {
    my ( $class, $type ) = @_;
    bless {
        type => $type,

        # Settings of current connection
        settings => {
            &SETTINGS_HEADER_TABLE_SIZE      => 1_024,
            &SETTINGS_ENABLE_PUSH            => 1,
            &SETTINGS_MAX_CONCURRENT_STREAMS => 100,
            &SETTINGS_INITIAL_WINDOW_SIZE    => 65_535,
        },
        streams => {},

        last_stream => ( $type eq 'server' ) ? 2 : 1,

        # HPACK. Reference Set
        reference_set => {},

        # HPACK. Header Table
        header_table => [],

        # HPACK. Header Table size
        ht_size => 0,

        # HPACK. Emitted headers
        emitted_headers => [],

        # Current frame
        frame => {},

        # Current error
        error => undef
      },
      $class;
}

sub is_client {
    my $self = shift;
    return $self->{type} eq 'client';
}

sub new_stream {
    my $self = shift;
    my $stream = $self->{last_stream} += 2;
    $self->{streams}->{$stream} = { 'state' => 'idle', };
}

sub frame {
    shift->{frame};
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

1;
