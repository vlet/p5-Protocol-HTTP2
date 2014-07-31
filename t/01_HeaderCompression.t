use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2Test;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Constants qw(:endpoints :limits);

BEGIN {
    use_ok( 'Protocol::HTTP2::HeaderCompression',
        qw(int_encode int_decode str_encode str_decode headers_decode headers_encode)
    );
}

subtest 'int_encode' => sub {
    ok binary_eq( int_encode( 0,     8 ), pack( "C",  0 ) );
    ok binary_eq( int_encode( 0xFD,  8 ), pack( "C",  0xFD ) );
    ok binary_eq( int_encode( 0xFF,  8 ), pack( "C*", 0xFF, 0x00 ) );
    ok binary_eq( int_encode( 0x100, 8 ), pack( "C*", 0xFF, 0x01 ) );
    ok binary_eq( int_encode( 1337,  5 ), pack( "C*", 31, 154, 10 ) );
};

subtest 'int_decode' => sub {
    my $buf = pack( "C*", 31, 154, 10 );
    my $int = 0;
    is int_decode( \$buf, 0, \$int, 5 ), 3;
    is $int, 1337;
};

subtest 'str_encode' => sub {

    ok binary_eq( str_encode('//ee'), hstr("8361 8297") );

};

subtest 'str_decode' => sub {
    my $s = hstr(<<EOF);
    93aa 69d2 9ae4 52a9 a74a 6b13 005d a5c0
    b5fc 1c7f
EOF
    str_decode( \$s, 0, \my $res );
    is $res, "nghttpd nghttp2/0.4.0-DEV", "str_decode";
};

subtest 'encode requests' => sub {

    my $con = Protocol::HTTP2::Connection->new(CLIENT);
    my $ctx = $con->encode_context;

    ok binary_eq(
        headers_encode(
            $ctx,
            [
                ':method'    => 'GET',
                ':scheme'    => 'http',
                ':path'      => '/',
                ':authority' => 'www.example.com',
            ]
        ),
        hstr(<<EOF) );
        8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4
        ff
EOF

    ok binary_eq(
        headers_encode(
            $ctx,
            [
                ':method'       => 'GET',
                ':scheme'       => 'http',
                ':path'         => '/',
                ':authority'    => 'www.example.com',
                'cache-control' => 'no-cache',
            ]
        ),
        hstr(<<EOF) );
        c1c0 bfbe 5886 a8eb 1064 9cbf
EOF

    ok binary_eq(
        headers_encode(
            $ctx,
            [
                ':method'    => 'GET',
                ':scheme'    => 'https',
                ':path'      => '/index.html',
                ':authority' => 'www.example.com',
                'custom-key' => 'custom-value',
            ]
        ),
        hstr(<<EOF) );
        c287 85c1 4088 25a8 49e9 5ba9 7d7f 8925
        a849 e95b b8e8 b4bf
EOF

};

subtest 'encode responses' => sub {

    my $con = Protocol::HTTP2::Connection->new(SERVER);
    my $ctx = $con->encode_context;
    $ctx->{max_ht_size} = 256;

    ok binary_eq(
        headers_encode(
            $ctx,
            [
                ':status'       => '302',
                'cache-control' => 'private',
                'date'          => 'Mon, 21 Oct 2013 20:13:21 GMT',
                'location'      => 'https://www.example.com',
            ]
        ),
        hstr(<<EOF) );
        4882 6402 5885 aec3 771a 4b61 96d0 7abe
        9410 54d4 44a8 2005 9504 0b81 66e0 82a6
        2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8
        e9ae 82ae 43d3
EOF

    is $ctx->{ht_size} => 222, 'ht_size ok';

    ok binary_eq(
        headers_encode(
            $ctx,
            [
                ':status'       => 200,
                'cache-control' => 'private',
                'date'          => 'Mon, 21 Oct 2013 20:13:21 GMT',
                'location'      => 'https://www.example.com',
            ]
        ),
        hstr("88c1 c0bf")
    );

    is $ctx->{ht_size} => 222, 'ht_size ok';

    ok binary_eq(
        headers_encode(
            $ctx,
            [
                ':status'          => 200,
                'cache-control'    => 'private',
                'date'             => 'Mon, 21 Oct 2013 20:13:22 GMT',
                'location'         => 'https://www.example.com',
                'content-encoding' => 'gzip',
                'set-cookie' =>
                  'foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1',
            ]
        ),
        hstr(<<EOF) );
    bec1 7f01 96d0 7abe 9410 54d4 44a8 2005
    9504 0b81 66e0 84a6 2d1b ffbf 5a83 9bd9
    ab77 ad94 e782 1dd7 f2e6 c7b3 35df dfcd
    5b39 60d5 af27 087f 3672 c1ab 270f b529
    1f95 8731 6065 c003 ed4e e5b1 063d 5007
EOF
    is $ctx->{ht_size} => 255, 'ht_size ok';

};

done_testing();
__END__

subtest 'decode requests' => sub {
    my $decoder = Protocol::HTTP2::HeaderCompression->new;

    is $decoder->headers_decode( \hstr(<<EOF), \my @headers ), 17;
            8287 8644 8ce7 cf9b ebe8 9b6f b16f a9b6
            ff
EOF
    is_deeply \@headers,
      [
        [ ':method'    => 'GET' ],
        [ ':scheme'    => 'http' ],
        [ ':path'      => '/' ],
        [ ':authority' => 'www.example.com' ]
      ]
      or diag explain \@headers;

    @headers = ();

    is $decoder->headers_decode( \hstr(<<EOF), \@headers ), 8;
        5c86 b9b9 9495 56bf
EOF

    is_deeply \@headers, [ [ 'cache-control' => 'no-cache' ], ]
      or diag explain \@headers;

    is_deeply $decoder->{_reference_set},
      {
        ':method'       => 'GET',
        ':scheme'       => 'http',
        ':path'         => '/',
        ':authority'    => 'www.example.com',
        'cache-control' => 'no-cache',
      }
      or diag explain $decoder->{_reference_set};

    @headers = ();

    is $decoder->headers_decode( \hstr(<<EOF), \@headers ), 25;
    3085 8c8b 8440 8857 1c5c db73 7b2f af89
    571c 5cdb 7372 4d9c 57
EOF

    is_deeply \@headers,
      [
        [ ':method'    => 'GET' ],
        [ ':scheme'    => 'https' ],
        [ ':path'      => '/index.html' ],
        [ ':authority' => 'www.example.com' ],
        [ 'custom-key' => 'custom-value' ],
      ]
      or diag explain \@headers;

    is_deeply $decoder->{_reference_set},
      {
        ':method'    => 'GET',
        ':scheme'    => 'https',
        ':path'      => '/index.html',
        ':authority' => 'www.example.com',
        'custom-key' => 'custom-value',
      },
      "Reference set"
      or diag explain $decoder->{_reference_set};

    is_deeply $decoder->{_header_table},
      [
        [ 'custom-key'    => 'custom-value' ],
        [ ':path'         => '/index.html' ],
        [ ':scheme'       => 'https' ],
        [ 'cache-control' => 'no-cache' ],
        [ ':authority'    => 'www.example.com' ],
        [ ':path'         => '/' ],
        [ ':scheme'       => 'http' ],
        [ ':method'       => 'GET' ],
      ]
      or diag explain $decoder->{_header_table};

};

subtest 'decode responses' => sub {
    my $decoder = Protocol::HTTP2::HeaderCompression->new;

    $decoder->{_max_ht_size} = 256;

    is $decoder->headers_decode( \hstr(<<EOF), \my @headers ), 51;
        4882 4017 5985 bf06 724b 9763 93d6 dbb2
        9884 de2a 7188 0506 2098 5131 09b5 6ba3
        7191 adce bf19 8e7e 7cf9 bebe 89b6 fb16
        fa9b 6f
EOF

    is_deeply \@headers, [
        [ ':status'       => '302' ],
        [ 'cache-control' => 'private' ],
        [ 'date'          => 'Mon, 21 Oct 2013 20:13:21 GMT' ],
        [ 'location'      => 'https://www.example.com' ],

    ] or diag explain \@headers;

    @headers = ();

    is $decoder->headers_decode( \hstr("8c"), \@headers ), 1;

    is_deeply \@headers, [ [ ':status' => '200' ], ] or diag explain \@headers;

    @headers = ();

    is $decoder->headers_decode( \hstr(<<EOF), \@headers ), 84;
    8484 4393 d6db b298 84de 2a71 8805 0620
    9851 3111 b56b a35e 84ab dd97 ff84 8483
    837b b1e0 d6cf 9f6e 8f9f d3e5 f6fa 76fe
    fd3c 7edf 9eff 1f2f 0f3c fe9f 6fcf 7f8f
    879f 61ad 4f4c c9a9 73a2 200e c372 5e18
    b1b7 4e3f
EOF

    is_deeply \@headers,
      [
        [ 'cache-control'    => 'private' ],
        [ 'date'             => 'Mon, 21 Oct 2013 20:13:22 GMT' ],
        [ 'content-encoding' => 'gzip' ],
        [ 'location'         => 'https://www.example.com' ],
        [ ':status'          => '200' ],
        [
            'set-cookie' =>
              'foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1'
        ],
      ]
      or diag explain \@headers;

};

done_testing;

