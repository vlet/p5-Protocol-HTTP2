package Protocol::HTTP2::Frame::Altsvc;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:endpoints :errors :limits);
use Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};
    my $origin;

    # The ALTSVC frame is intended for receipt by clients
    if ( $con->{type} == SERVER ) {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    my $offset = 8;

    if ( $length < $offset ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my ( $max_age, $port, undef, $proto_len ) =
      unpack( 'NnC2', substr( $$buf_ref, $buf_offset, $offset ) );

    if ( $proto_len > $length - ( $offset + 1 ) ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my $proto_id = substr $$buf_ref, $buf_offset + $offset, $proto_len;
    $offset += $proto_len;
    my $host_len = unpack( 'C', substr( $$buf_ref, $buf_offset + $offset, 1 ) );
    $offset += 1;

    if ( $host_len > $length - $offset ) {
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my $host = substr $$buf_ref, $buf_offset + $offset, $host_len;
    $offset += $host_len;

    # An ALTSVC frame on stream 0 indicates that the conveyed alternative
    # service is associated with the origin contained in the Origin field of
    # the frame.
    if ( $frame_ref->{stream} == 0 ) {
        $origin = substr $$buf_ref, $buf_offset + $offset, $length - $offset;
    }

    $con->altsvc( $max_age, $proto_id, $port, $host, $origin );

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream_id, $data_ref ) = @_;

    unless ( $data_ref
        && ref $data_ref eq 'HASH'
        && scalar( grep { exists $data_ref->{$_} } (qw(port proto host)) ) ==
        3 )
    {
        $con->error(INTERNAL_ERROR);
        return undef;
    }

    return pack( 'NnC2',
        $data_ref->{max_age} || DEFAULT_ALTSVC_MAX_AGE,
        $data_ref->{port}, 0, length( $data_ref->{proto} ) )
      . $data_ref->{proto}
      . pack( 'C', length( $data_ref->{host} ) )
      . $data_ref->{host}
      . (
        ( $stream_id == 0 && exists $data_ref->{origin} )
        ? $data_ref->{origin}
        : ''
      );

}

1;
