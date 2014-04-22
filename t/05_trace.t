use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok( 'Protocol::HTTP2::Trace', qw(tracer bin2hex) );
}

subtest 'bin2hex' => sub {
    is bin2hex("ABCDEFGHIJKLMNOPQR"),
      "4142 4344 4546 4748 494a 4b4c 4d4e 4f50\n5152 ";
};

done_testing;

