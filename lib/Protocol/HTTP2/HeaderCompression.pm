package Protocol::HTTP2::HeaderCompression;
use strict;
use warnings;
use Protocol::HTTP2::Huffman;
use Protocol::HTTP2::StaticTable;
use Protocol::HTTP2::Constants qw(:errors :settings :limits);
use Protocol::HTTP2::Trace qw(tracer bin2hex);
use Exporter qw(import);
our @EXPORT_OK = qw(int_encode int_decode str_encode str_decode headers_decode
  headers_encode);

sub int_encode {
    my ( $int, $N ) = @_;
    $N ||= 7;
    my $ff = ( 1 << $N ) - 1;

    if ( $int < $ff ) {
        return pack 'C', $int;
    }

    my $res = pack 'C', $ff;
    $int -= $ff;

    while ( $int >= 0x80 ) {
        $res .= pack( 'C', ( $int & 0x7f ) | 0x80 );
        $int >>= 7;
    }

    return $res . pack( 'C', $int );
}

# int_decode()
#
# arguments:
#   buf_ref    - ref to buffer with encoded data
#   buf_offset - offset in buffer
#   int_ref    - ref to scalar where result will be stored
#   N          - bits in first byte
#
# returns: count of readed bytes of encoded integer
#          or undef on error (malformed data)

sub int_decode {
    my ( $buf_ref, $buf_offset, $int_ref, $N ) = @_;
    return undef if length($$buf_ref) - $buf_offset <= 0;
    $N ||= 7;
    my $ff = ( 1 << $N ) - 1;

    $$int_ref = $ff & vec( $$buf_ref, $buf_offset, 8 );
    return 1 if $$int_ref < $ff;

    my $l = length($$buf_ref) - $buf_offset - 1;

    for my $i ( 1 .. $l ) {
        return undef if $i > MAX_INT_SIZE;
        my $s = vec( $$buf_ref, $i + $buf_offset, 8 );
        $$int_ref += ( $s & 0x7f ) << ( $i - 1 ) * 7;
        return $i + 1 if $s < 0x80;
    }

    return undef;
}

sub str_encode {
    my $str      = shift;
    my $huff_str = huffman_encode($str);
    my $pack;
    if ( length($huff_str) < length($str) ) {
        $pack = int_encode( length($huff_str), 7 );
        vec( $pack, 7, 1 ) = 1;
        $pack .= $huff_str;
    }
    else {
        $pack = int_encode( length($str), 7 );
        $pack .= $str;
    }
    return $pack;
}

# str_decode()
# arguments:
#   buf_ref    - ref to buffer with encoded data
#   buf_offset - offset in buffer
#   str_ref    - ref to scalar where result will be stored
# returns: count of readed bytes of encoded data

sub str_decode {
    my ( $buf_ref, $buf_offset, $str_ref ) = @_;
    my $offset = int_decode( $buf_ref, $buf_offset, \my $l, 7 );
    return undef
      unless defined $offset
      && length($$buf_ref) - $buf_offset - $offset >= $l;

    $$str_ref = substr $$buf_ref, $offset + $buf_offset, $l;
    $$str_ref = huffman_decode($$str_ref)
      if vec( $$buf_ref, $buf_offset * 8 + 7, 1 ) == 1;
    return $offset + $l;
}

sub evict_ht {
    my ( $context, $size ) = @_;
    my @evicted;

    my $ht = $context->{header_table};

    while ( $context->{ht_size} + $size >
        $context->{settings}->{&SETTINGS_HEADER_TABLE_SIZE} )
    {
        my $n      = $#$ht;
        my $kv_ref = pop @$ht;
        $context->{ht_size} -=
          32 + length( $kv_ref->[0] ) + length( $kv_ref->[1] );
        tracer->debug( sprintf "Evicted header [%i] %s = %s\n",
            $n + 1, @$kv_ref );
        push @evicted, [ $n, @$kv_ref ];
    }
    return @evicted;
}

sub add_to_ht {
    my ( $context, $key, $value ) = @_;
    my $size = length($key) + length($value) + 32;
    return () if $size > $context->{settings}->{&SETTINGS_HEADER_TABLE_SIZE};

    my @evicted = evict_ht( $context, $size );

    my $ht = $context->{header_table};
    my $kv_ref = [ $key, $value ];

    unshift @$ht, $kv_ref;
    $context->{ht_size} += $size;
    return @evicted;
}

sub headers_decode {
    my ( $con, $buf_ref, $buf_offset, $length, $stream_id ) = @_;

    my $context = $con->decode_context;

    my $ht = $context->{header_table};
    my $eh = $context->{emitted_headers};

    my $offset = 0;

    while ( $offset < $length ) {

        my $f = vec( $$buf_ref, $buf_offset + $offset, 8 );
        tracer->debug("\toffset: $offset\n");

        # Indexed Header
        if ( $f & 0x80 ) {
            my $size =
              int_decode( $buf_ref, $buf_offset + $offset, \my $index, 7 );
            return $offset unless $size;

            # DECODING ERROR
            if ( $index == 0 ) {
                tracer->error("Indexed header with zero index\n");
                $con->error(COMPRESSION_ERROR);
                return undef;
            }

            tracer->debug("\tINDEXED($index) HEADER\t");

            # Static table or Header Table entry
            if ( $index <= @stable ) {
                my ( $key, $value ) = @{ $stable[ $index - 1 ] };
                push @$eh, $key, $value;
                tracer->debug("$key = $value\n");
            }
            elsif ( $index > @stable + @$ht ) {
                tracer->error(
                        "Indexed header with index out of header table: "
                      . $index
                      . "\n" );
                $con->error(COMPRESSION_ERROR);
                return undef;
            }
            else {
                my $kv_ref = $ht->[ $index - @stable - 1 ];

                push @$eh, @$kv_ref;
                tracer->debug("$kv_ref->[0] = $kv_ref->[1]\n");
            }

            $offset += $size;
        }

        # Literal Header Field - New Name
        elsif ( $f == 0x40 || $f == 0x00 || $f == 0x10 ) {
            my $key_size =
              str_decode( $buf_ref, $buf_offset + $offset + 1, \my $key );
            return $offset unless $key_size;

            if ( $key_size == 1 ) {
                tracer->error("Empty literal header name");
                $con->error(COMPRESSION_ERROR);
                return undef;
            }

            if ( $key =~ /[^a-z0-9\!\#\$\%\&\'\*\+\-\^\_\`]/ ) {
                tracer->error("Illegal characters in header name");
                $con->stream_error( $stream_id, PROTOCOL_ERROR );
                return undef;
            }

            my $value_size =
              str_decode( $buf_ref, $buf_offset + $offset + 1 + $key_size,
                \my $value );
            return $offset unless $value_size;

            # Emitting header
            push @$eh, $key, $value;

            # Add to index
            if ( $f == 0x40 ) {
                add_to_ht( $context, $key, $value );
            }
            tracer->debug( sprintf "\tLITERAL(new) HEADER\t%s: %s\n",
                $key, substr( $value, 0, 30 ) );

            $offset += 1 + $key_size + $value_size;
        }

        # Literal Header Field - Indexed Name
        elsif (( $f & 0xC0 ) == 0x40
            || ( $f & 0xF0 ) == 0x00
            || ( $f & 0xF0 ) == 0x10 )
        {
            my $size = int_decode( $buf_ref, $buf_offset + $offset,
                \my $index, ( $f & 0xC0 ) == 0x40 ? 6 : 4 );
            return $offset unless $size;

            my $value_size =
              str_decode( $buf_ref, $buf_offset + $offset + $size, \my $value );
            return $offset unless $value_size;

            my $key;

            if ( $index <= @stable ) {
                $key = $stable[ $index - 1 ]->[0];
            }
            elsif ( $index > @stable + @$ht ) {
                tracer->error(
                        "Literal header with index out of header table: "
                      . $index
                      . "\n" );
                $con->error(COMPRESSION_ERROR);
                return undef;
            }
            else {
                $key = $ht->[ $index - @stable - 1 ]->[0];
            }

            # Emitting header
            push @$eh, $key, $value;

            # Add to index
            if ( ( $f & 0xC0 ) == 0x40 ) {
                add_to_ht( $context, $key, $value );
            }
            tracer->debug("\tLITERAL($index) HEADER\t$key: $value\n");

            $offset += $size + $value_size;
        }

        # Encoding Context Update - Maximum Header Table Size change
        elsif ( ( $f & 0xE0 ) == 0x20 ) {
            my $size =
              int_decode( $buf_ref, $buf_offset + $offset, \my $ht_size, 5 );
            return $offset unless $size;

            # It's not possible to increase size of HEADER_TABLE
            if (
                $ht_size > $context->{settings}->{&SETTINGS_HEADER_TABLE_SIZE} )
            {
                tracer->error( "Peer attempt to increase "
                      . "SETTINGS_HEADER_TABLE_SIZE higher than current size: "
                      . "$ht_size > "
                      . $context->{settings}->{&SETTINGS_HEADER_TABLE_SIZE} );
                $con->error(COMPRESSION_ERROR);
                return undef;
            }
            $context->{settings}->{&SETTINGS_HEADER_TABLE_SIZE} = $ht_size;
            evict_ht( $context, 0 );
            $offset += $size;
        }

        # Encoding Error
        else {
            tracer->error( sprintf( "Unknown header type: %08b", $f ) );
            $con->error(COMPRESSION_ERROR);
            return undef;
        }
    }
    return $offset;
}

sub headers_encode {
    my ( $context, $headers ) = @_;
    my $res = '';
    my $ht  = $context->{header_table};

  HLOOP:
    for my $n ( 0 .. $#$headers / 2 ) {
        my $header = lc( $headers->[ 2 * $n ] );
        my $value  = $headers->[ 2 * $n + 1 ];
        my $hdr;

        tracer->debug("Encoding header: $header = $value\n");

        for my $i ( 0 .. $#$ht ) {
            next
              unless $ht->[$i]->[0] eq $header
              && $ht->[$i]->[1] eq $value;
            $hdr = int_encode( $i + @stable + 1, 7 );
            vec( $hdr, 7, 1 ) = 1;
            $res .= $hdr;
            tracer->debug(
                "\talready in header table, index " . ( $i + 1 ) . "\n" );
            next HLOOP;
        }

        # 7.1 Indexed header field representation
        if ( exists $rstable{ $header . ' ' . $value } ) {
            $hdr = int_encode( $rstable{ $header . ' ' . $value }, 7 );
            vec( $hdr, 7, 1 ) = 1;
            tracer->debug( "\tIndexed header "
                  . $rstable{ $header . ' ' . $value }
                  . " from table\n" );
        }

        # 7.2.1 Literal Header Field with Incremental Indexing
        # (Indexed Name)
        elsif ( exists $rstable{ $header . ' ' } ) {
            $hdr = int_encode( $rstable{ $header . ' ' }, 6 );
            vec( $hdr, 3, 2 ) = 1;
            $hdr .= str_encode($value);
            add_to_ht( $context, $header, $value );
            tracer->debug( "\tLiteral header "
                  . $rstable{ $header . ' ' }
                  . " indexed name\n" );
        }

        # 7.2.1 Literal Header Field with Incremental Indexing
        # (New Name)
        else {
            $hdr = pack( 'C', 0x40 );
            $hdr .= str_encode($header) . str_encode($value);
            add_to_ht( $context, $header, $value );
            tracer->debug("\tLiteral header new name\n");
        }

        $res .= $hdr;
    }

    return $res;
}

1;
