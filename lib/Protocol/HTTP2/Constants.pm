package Protocol::HTTP2::Constants;
use strict;
use warnings;
use constant {

    # Header Compression
    MAX_INT_SIZE     => 4,
    MAX_PAYLOAD_SIZE => ( 1 << 24 ) - 1,

    # Frame
    FRAME_HEADER_SIZE => 9,

    # Flow control
    MAX_FCW_SIZE => ( 1 << 31 ) - 1,

    # Settings defaults
    DEFAULT_HEADER_TABLE_SIZE      => 4_096,
    DEFAULT_ENABLE_PUSH            => 1,
    DEFAULT_MAX_CONCURRENT_STREAMS => 100,
    DEFAULT_INITIAL_WINDOW_SIZE    => 65_535,
    DEFAULT_MAX_FRAME_SIZE         => 16_384,
    DEFAULT_MAX_HEADER_LIST_SIZE   => 65_536,

    # Priority
    DEFAULT_WEIGHT => 16,

    # Stream states
    IDLE        => 1,
    RESERVED    => 2,
    OPEN        => 3,
    HALF_CLOSED => 4,
    CLOSED      => 5,

    # Endpoint types
    CLIENT => 1,
    SERVER => 2,

    # Preface string
    PREFACE => "PRI * HTTP/2.0\x0d\x0a\x0d\x0aSM\x0d\x0a\x0d\x0a",

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

    # Flags
    ACK           => 0x1,
    END_STREAM    => 0x1,
    END_HEADERS   => 0x4,
    PADDED        => 0x8,
    PRIORITY_FLAG => 0x20,

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
    HTTP_1_1_REQUIRED   => 13,

    # SETTINGS
    SETTINGS_HEADER_TABLE_SIZE      => 1,
    SETTINGS_ENABLE_PUSH            => 2,
    SETTINGS_MAX_CONCURRENT_STREAMS => 3,
    SETTINGS_INITIAL_WINDOW_SIZE    => 4,
    SETTINGS_MAX_FRAME_SIZE         => 5,
    SETTINGS_MAX_HEADER_LIST_SIZE   => 6,

};

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = (
    frame_types => [
        qw(DATA HEADERS PRIORITY RST_STREAM SETTINGS PUSH_PROMISE
          PING GOAWAY WINDOW_UPDATE CONTINUATION)
    ],
    errors => [
        qw(NO_ERROR PROTOCOL_ERROR INTERNAL_ERROR FLOW_CONTROL_ERROR
          SETTINGS_TIMEOUT STREAM_CLOSED FRAME_SIZE_ERROR REFUSED_STREAM CANCEL
          COMPRESSION_ERROR CONNECT_ERROR ENHANCE_YOUR_CALM INADEQUATE_SECURITY
          HTTP_1_1_REQUIRED
          )
    ],
    preface  => [qw(PREFACE)],
    flags    => [qw(ACK END_STREAM END_HEADERS PADDED PRIORITY_FLAG)],
    settings => [
        qw(SETTINGS_HEADER_TABLE_SIZE SETTINGS_ENABLE_PUSH
          SETTINGS_MAX_CONCURRENT_STREAMS SETTINGS_INITIAL_WINDOW_SIZE
          SETTINGS_MAX_FRAME_SIZE SETTINGS_MAX_HEADER_LIST_SIZE)
    ],
    limits => [
        qw(MAX_INT_SIZE MAX_PAYLOAD_SIZE MAX_FCW_SIZE DEFAULT_WEIGHT
          DEFAULT_HEADER_TABLE_SIZE
          DEFAULT_MAX_CONCURRENT_STREAMS
          DEFAULT_ENABLE_PUSH
          DEFAULT_INITIAL_WINDOW_SIZE
          DEFAULT_MAX_FRAME_SIZE
          DEFAULT_MAX_HEADER_LIST_SIZE
          FRAME_HEADER_SIZE)
    ],
    states    => [qw(IDLE RESERVED OPEN HALF_CLOSED CLOSED)],
    endpoints => [qw(CLIENT SERVER)],
);

my %reverse;
{
    no strict 'refs';
    for my $k ( keys %EXPORT_TAGS ) {
        for my $v ( @{ $EXPORT_TAGS{$k} } ) {
            $reverse{$k}{ &{$v} } = $v;
        }
    }
}

sub const_name {
    my ( $tag, $value ) = @_;
    exists $reverse{$tag} ? ( $reverse{$tag}{$value} || '' ) : '';
}

our @EXPORT_OK = ( qw(const_name), map { @$_ } values %EXPORT_TAGS );

1;
