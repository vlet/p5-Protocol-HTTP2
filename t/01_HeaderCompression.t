use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2Test;

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

    ok binary_eq( str_encode('//ee'), hstr("8339 D6BF") );

};

subtest 'str_decode' => sub {
    my $s = hstr(<<EOF);
    93ba aadc ebe9 35d5 56e7 5e47 07e0
    7c33 68ef fc7f
EOF
    str_decode( \$s, 0, \my $res );
    is $res, "nghttpd nghttp2/0.4.0-DEV", "str_decode";
};

done_testing();
__END__

subtest 'encode requests' => sub {
    my $encoder = Protocol::HTTP2::HeaderCompression->new;

    ok binary_eq(
        $encoder->headers_encode(
            [
                [ ':method'    => 'GET' ],
                [ ':scheme'    => 'http' ],
                [ ':path'      => '/' ],
                [ ':authority' => 'www.example.com' ]
            ]
        ),
        hstr(<<EOF) );
        8287 8644 8ce7 cf9b ebe8 9b6f b16f a9b6
        ff
EOF

    ok binary_eq(
        $encoder->headers_encode(
            [
                [ ':method'       => 'GET' ],
                [ ':scheme'       => 'http' ],
                [ ':path'         => '/' ],
                [ ':authority'    => 'www.example.com' ],
                [ 'cache-control' => 'no-cache' ],
            ]
        ),
        hstr(<<EOF) );
        5c86 b9b9 9495 56bf
EOF

    ok binary_eq(
        $encoder->headers_encode(
            [
                [ ':method'    => 'GET' ],
                [ ':scheme'    => 'https' ],
                [ ':path'      => '/index.html' ],
                [ ':authority' => 'www.example.com' ],
                [ 'custom-key' => 'custom-value' ],
            ]
        ),
        hstr(<<EOF) );
    3085 8c8b 8440 8857 1c5c db73 7b2f af89
    571c 5cdb 7372 4d9c 57
EOF

};

subtest 'encode responses' => sub {
    my $encoder = Protocol::HTTP2::HeaderCompression->new;
    $encoder->{_max_ht_size} = 256;

    ok binary_eq(
        $encoder->headers_encode(
            [
                [ ':status'       => '302' ],
                [ 'cache-control' => 'private' ],
                [ 'date'          => 'Mon, 21 Oct 2013 20:13:21 GMT' ],
                [ 'location'      => 'https://www.example.com' ],
            ]
        ),
        hstr(<<EOF) );
    4882 4017 5985 bf06 724b 9763 93d6 dbb2
    9884 de2a 7188 0506 2098 5131 09b5 6ba3
    7191 adce bf19 8e7e 7cf9 bebe 89b6 fb16
    fa9b 6f
EOF

    ok binary_eq(
        $encoder->headers_encode(
            [
                [ ':status'       => 200 ],
                [ 'cache-control' => 'private' ],
                [ 'date'          => 'Mon, 21 Oct 2013 20:13:21 GMT' ],
                [ 'location'      => 'https://www.example.com' ],
            ]
        ),
        hstr("8c")
    );

    ok binary_eq(
        $encoder->headers_encode(
            [
                [ ':status'          => 200 ],
                [ 'cache-control'    => 'private' ],
                [ 'date'             => 'Mon, 21 Oct 2013 20:13:22 GMT' ],
                [ 'location'         => 'https://www.example.com' ],
                [ 'content-encoding' => 'gzip' ],
                [
                    'set-cookie' =>
                      'foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1'
                ],
            ]
        ),
        hstr(<<EOF) );
    4393 d6db b298 84de 2a71 8805 0620
    9851 3111 b56b a35e 84ab dd97 ff
    7b b1e0 d6cf 9f6e 8f9f d3e5 f6fa 76fe
    fd3c 7edf 9eff 1f2f 0f3c fe9f 6fcf 7f8f
    879f 61ad 4f4c c9a9 73a2 200e c372 5e18
    b1b7 4e3f
EOF

};

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

