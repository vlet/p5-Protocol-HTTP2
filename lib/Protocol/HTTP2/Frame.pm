package Protocol::HTTP2::Frame;
use strict;
use warnings;
use Protocol::HTTP2::Trace qw(tracer);
use Protocol::HTTP2::Constants
  qw(const_name :frame_types :errors :preface :states :flags);
use Protocol::HTTP2::Frame::Data;
use Protocol::HTTP2::Frame::Headers;
use Protocol::HTTP2::Frame::Priority;
use Protocol::HTTP2::Frame::Rst_stream;
use Protocol::HTTP2::Frame::Settings;
use Protocol::HTTP2::Frame::Push_promise;
use Protocol::HTTP2::Frame::Ping;
use Protocol::HTTP2::Frame::Goaway;
use Protocol::HTTP2::Frame::Window_update;
use Protocol::HTTP2::Frame::Continuation;
use Protocol::HTTP2::Frame::Altsvc;
use Protocol::HTTP2::Frame::Blocked;

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
    &BLOCKED       => 'Blocked',
);

my %decoder =
  map { $_ => \&{ 'Protocol::HTTP2::Frame::' . $frame_class{$_} . '::decode' } }
  keys %frame_class;

my %encoder =
  map { $_ => \&{ 'Protocol::HTTP2::Frame::' . $frame_class{$_} . '::encode' } }
  keys %frame_class;

sub frame_encode {
    my ( $con, $type, $flags, $stream_id, $data ) = @_;

    my $payload = $encoder{$type}->( $con, \$flags, $stream_id, $data );

    # Sended frame may change state of stream
    $con->state_machine( 'send', $type, $flags, $stream_id )
      if $type != SETTINGS && $type != GOAWAY && $stream_id != 0;

    pack( 'nC2N', length($payload), $type, $flags, $stream_id ) . $payload;
}

sub preface_decode {
    my ( $con, $buf_ref, $buf_offset ) = @_;
    return 0 if length($$buf_ref) - $buf_offset < length(PREFACE);
    return
      index( $$buf_ref, PREFACE, $buf_offset ) == -1 ? undef : length(PREFACE);
}

sub preface_encode {
    PREFACE;
}

sub frame_decode {
    my ( $con, $buf_ref, $buf_offset ) = @_;
    return 0 if length($$buf_ref) - $buf_offset < 8;

    my ( $length, $type, $flags, $stream_id ) =
      unpack( 'nC2N', substr( $$buf_ref, $buf_offset, 8 ) );
    tracer->debug(
        sprintf "TYPE = %s(%i), FLAGS = %08b, STREAM_ID = $stream_id, "
          . "LENGTH = %i\n",
        const_name( "frame_types", $type ),
        $type,
        $flags,
        $stream_id,
        $length
    );

    # Unknown type of frame
    if ( !exists $frame_class{$type} ) {
        tracer->debug("Unknown type of frame: $type\n");
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    $length    &= 0x3FFF;
    $stream_id &= 0x7FFF_FFFF;

    return 0 if length($$buf_ref) - $buf_offset - 8 - $length < 0;

    $con->decode_context->{frame} = {
        type   => $type,
        flags  => $flags,
        length => $length,
        stream => $stream_id,
    };

    # Create new stream structure
    # Error when stream_id is invalid
    if (   $stream_id
        && !$con->stream($stream_id)
        && !$con->new_peer_stream($stream_id) )
    {
        tracer->debug("Peer send invalid stream id: $stream_id\n");
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    return undef
      unless
      defined $decoder{$type}->( $con, $buf_ref, $buf_offset + 8, $length );

    # Arrived frame may change state of stream
    $con->state_machine( 'recv', $type, $flags, $stream_id )
      if $type != SETTINGS && $type != GOAWAY && $stream_id != 0;

    return 8 + $length;
}

1;
