use strict;
use warnings;
use Test::More;
use Data::Dumper;
BEGIN { use_ok('Protocol::HTTP2::Huffman') }

sub b2h {
    unpack 'H*', $_[0];
}

my $example = "www.example.com";
my $s       = huffman_encode($example);

is b2h($s), "e7cf9bebe89b6fb16fa9b6ff", "encode";
is huffman_decode($s), $example, "decode";

done_testing();
