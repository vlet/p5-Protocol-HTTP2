use strict;
use warnings;
use Test::More;
use Data::Dumper;
BEGIN { use_ok('Protocol::HTTP2::Huffman') }

use lib 't/lib';
use PH2Test;

my $example = "www.example.com";
my $s       = huffman_encode($example);

ok binary_eq( $s, hstr("f1e3 c2e5 f23a 6ba0 ab90 f4ff") ), "encode";
is huffman_decode($s), $example, "decode";

done_testing();
