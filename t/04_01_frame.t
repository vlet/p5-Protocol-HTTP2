use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Context;

BEGIN {
    use_ok('Protocol::HTTP2::Frame');
}

sub hstr {
    my $str = shift;
    $str =~ s/\s//g;
    my @a = ( $str =~ /../g );
    return pack "C*", map { hex $_ } @a;
}

subtest 'decode_request' => sub {

    my $data1 = hstr(<<EOF);

505249202a20485454502f322e300d0a0d0a534d0d0a0d0a000a0400000000000300000064040000ffff00380105000000014189128df07c1f19a4000f8306883dacb9963ee6db678856032a2f2a548aabdd97e5352be1625cbf7f008dbaaadcebc8e0fc0f866d1dff8f0000040100000000

EOF

    my $data2 = hstr(<<EOF);
    505249202a20485454502f322e300d0a0d0a534d0d0a0d0a000a040000000000040000ffff030000006400400105000000014087993c5cdc18eebf89128df07c1f19a4000f8346883dacb9963ee6db678957032a2f2a558aabdd97e5352be1625cbf7f018dbaaadcebc8e0fc0f866d1dff8f0000040100000000

EOF
    my $data = $data2;

    my $context = Protocol::HTTP2::Context->server;

    my $offset = preface_decode( \$data, 0 );
    is( $offset, 24, "Preface exists" ) or BAIL_OUT "preface?";
    while ( my $size = frame_decode( $context, \$data, $offset ) ) {
        $offset += $size;
    }
    ok( !defined $context->error ) or diag explain $context;

};

done_testing;
