package Protocol::HTTP2::Constants;
use strict;
use warnings;
use constant {

    # Header Compression
    MAX_INT_SIZE     => 4,
    MAX_PAYLOAD_SIZE => 1 << 14,

    # Settings defaults
    DEFAULT_HEADER_TABLE_SIZE      => 1_024,
    DEFAULT_ENABLE_PUSH            => 1,
    DEFAULT_MAX_CONCURRENT_STREAMS => 100,
    DEFAULT_INITIAL_WINDOW_SIZE    => 65_535,

    # Stream states
    IDLE        => 1,
    RESERVED    => 2,
    OPEN        => 3,
    HALF_CLOSED => 4,
    CLOSED      => 5,

    # Preface string
    PREFACE => "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n",

    # Frame types
    DATA          => 0,
    HEADERS       => 1,
    PRIORITY      => 2,
    RST_STREAM    => 3,
    SETTINGS      => 4,
    PUSH_PROMISE  => 5,
    PING          => 6,
    GOAWAY        => 7,
    WINDOW_UPDATE => 8,
    CONTINUATION  => 9,
    ALTSVC        => 0xA,

    # Flags
    ACK                 => 0x1,
    END_STREAM          => 0x1,
    END_SEGMENT         => 0x2,
    END_HEADERS         => 0x4,
    PAD_LOW             => 0x8,
    PAD_HIGH            => 0x10,
    PRIORITY_GROUP      => 0x20,
    PRIORITY_DEPENDENCY => 0x40,

    # Errors
    NO_ERROR            => 0,
    PROTOCOL_ERROR      => 1,
    INTERNAL_ERROR      => 2,
    FLOW_CONTROL_ERROR  => 3,
    SETTINGS_TIMEOUT    => 4,
    STREAM_CLOSED       => 5,
    FRAME_SIZE_ERROR    => 6,
    REFUSED_STREAM      => 7,
    CANCEL              => 8,
    COMPRESSION_ERROR   => 9,
    CONNECT_ERROR       => 10,
    ENHANCE_YOUR_CALM   => 11,
    INADEQUATE_SECURITY => 12,

    # SETTINGS
    SETTINGS_HEADER_TABLE_SIZE      => 1,
    SETTINGS_ENABLE_PUSH            => 2,
    SETTINGS_MAX_CONCURRENT_STREAMS => 3,
    SETTINGS_INITIAL_WINDOW_SIZE    => 4,

};

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = (
    frame_types => [
        qw(DATA HEADERS PRIORITY RST_STREAM SETTINGS PUSH_PROMISE
          PING GOAWAY WINDOW_UPDATE CONTINUATION ALTSVC)
    ],
    errors => [
        qw(NO_ERROR PROTOCOL_ERROR INTERNAL_ERROR FLOW_CONTROL_ERROR
          SETTINGS_TIMEOUT STREAM_CLOSED FRAME_SIZE_ERROR REFUSED_STREAM CANCEL
          COMPRESSION_ERROR CONNECT_ERROR ENHANCE_YOUR_CALM INADEQUATE_SECURITY
          )
    ],
    preface => [qw(PREFACE)],
    flags   => [
        qw(ACK END_STREAM END_SEGMENT END_HEADERS PAD_LOW PAD_HIGH
          PRIORITY_GROUP PRIORITY_DEPENDENCY)
    ],
    settings => [
        qw(SETTINGS_HEADER_TABLE_SIZE SETTINGS_ENABLE_PUSH
          SETTINGS_MAX_CONCURRENT_STREAMS SETTINGS_INITIAL_WINDOW_SIZE)
    ],
    limits => [
        qw(MAX_INT_SIZE MAX_PAYLOAD_SIZE
          DEFAULT_HEADER_TABLE_SIZE
          DEFAULT_MAX_CONCURRENT_STREAMS
          DEFAULT_ENABLE_PUSH
          DEFAULT_INITIAL_WINDOW_SIZE)
    ],
    states => [qw(IDLE RESERVED OPEN HALF_CLOSED CLOSED)],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

1;
