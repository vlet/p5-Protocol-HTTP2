package Protocol::HTTP2::Frame;
use strict;
use warnings;
use Protocol::HTTP2::Trace qw(tracer);
use Protocol::HTTP2::Constants qw(:frame_types :errors :preface);
use Protocol::HTTP2::Frame::Data;
use Protocol::HTTP2::Frame::Headers;
use Protocol::HTTP2::Frame::Settings;
use Protocol::HTTP2::Frame::Goaway;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(preface_decode frame_decode frame_encode);

# Table of payload decoders
my %frame_class = (
    &DATA          => 'Data',
    &HEADERS       => 'Headers',
    &PRIORITY      => 'Priority',
    &RST_STREAM    => 'Rst_stream',
    &SETTINGS      => 'Settings',
    &PUSH_PROMISE  => 'Push_promise',
    &PING          => 'Ping',
    &GOAWAY        => 'Goaway',
    &WINDOW_UPDATE => 'Window_update',
    &CONTINUATION  => 'Continuation',
    &ALTSVC        => 'Altsvc',
);

my %decoder =
  map { $_ => \&{ 'Protocol::HTTP2::Frame::' . $frame_class{$_} . '::decode' } }
  keys %frame_class;

my %encoder =
  map { $_ => \&{ 'Protocol::HTTP2::Frame::' . $frame_class{$_} . '::encode' } }
  keys %frame_class;

sub frame_encode {
    my ( $type, $flags, $stream, $data ) = @_;

    my $payload = $encoder{$type}->( \$flags, $stream, $data );
    pack( 'nC2N', length($payload), $type, $flags, $stream ) . $payload;
}

sub preface_decode {
    my ( $buf_ref, $buf_offset ) = @_;
    return 0 if length($$buf_ref) - $buf_offset < length(PREFACE);
    return
      index( $$buf_ref, PREFACE, $buf_offset ) == -1 ? undef : length(PREFACE);
}

sub frame_decode {
    my ( $context, $buf_ref, $buf_offset ) = @_;
    return 0 if length($$buf_ref) - $buf_offset < 8;

    my ( $length, $type, $flags, $stream ) =
      unpack( 'nC2N', substr( $$buf_ref, $buf_offset, 8 ) );
    tracer->debug(
        "TYPE = $type, FLAGS = $flags, STREAM = $stream, LENGTH = $length\n");

    # Unknown type of frame
    if ( !exists $frame_class{$type} ) {
        tracer->debug("Unknown type of frame: $type\n");
        $context->error(PROTOCOL_ERROR);
        return undef;
    }

    $length &= 0x3FFF;
    $stream &= 0x7FFF_FFFF;

    return 0 if length($$buf_ref) - $buf_offset - 8 - $length < 0;

    $context->{frame} = {
        type   => $type,
        flags  => $flags,
        length => $length,
        stream => $stream,
    };

    return
      defined $decoder{$type}->( $context, $buf_ref, $buf_offset + 8, $length )
      ? 8 + $length
      : undef;
}

1;
