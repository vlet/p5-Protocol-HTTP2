package Protocol::HTTP2::Context;
use strict;
use warnings;
use Protocol::HTTP2::Constants
  qw(:frame_types :errors :settings :flags :limits);
use Protocol::HTTP2::Frame;
use Carp;

sub new {
    my ( $class, $max_ht_size ) = @_;
    bless {
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
      $class;
}

1;
