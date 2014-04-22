package Protocol::HTTP2::Huffman;
use strict;
use warnings;
use Protocol::HTTP2::HuffmanCodes;
use Protocol::HTTP2::Trace qw(tracer);
our ( %hcodes, %rhcodes, $hre );
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(huffman_encode huffman_decode);

# Memory unefficient algorithm (well suited for short strings)

sub huffman_encode {
    my $s = shift;
    my $ret = my $bin = '';
    for my $i ( 0 .. length($s) - 1 ) {
        $bin .= $hcodes{ ord( substr $s, $i, 1 ) };
    }
    $bin .= substr( $hcodes{256}, 0, 8 - length($bin) % 8 ) if length($bin) % 8;
    return $ret . pack( 'B*', $bin );
}

sub huffman_decode {
    my $s = shift;
    my $bin = unpack( 'B*', $s );

    my $c = 0;
    $s = pack 'C*', map { $c += length; $rhcodes{$_} } ( $bin =~ /$hre/g );
    tracer->warning(
        sprintf(
            "malformed data in string at position %i, " . " length: %i",
            $c, length($bin)
        )
    ) if length($bin) - $c > 8;
    tracer->warning( "no huffman code 256 at the end of encoded string '$s': "
          . substr( $bin, $c )
          . "\n" )
      if $hcodes{256} !~ /^@{[ substr($bin, $c) ]}/;
    return $s;
}

1;
