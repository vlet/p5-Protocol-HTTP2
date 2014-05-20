use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2ClientServerTest;
use Test::TCP;
use Protocol::HTTP2;

my $host = '127.0.0.1';

subtest 'client/server' => sub {
    for my $opts (
        [ "without tls", [], [] ],
        [ "without tls, upgrade", [ upgrade => 1 ], [ upgrade => 1 ] ],
        [
            "tls/npn",
            [ npn => 1 ],
            [
                npn     => 1,
                tls_crt => 'examples/test.crt',
                tls_key => 'examples/test.key'
            ]
        ],
        [
            "tls/alpn",
            [ alpn => 1 ],
            [
                alpn    => 1,
                tls_crt => 'examples/test.crt',
                tls_key => 'examples/test.key'
            ]
        ],
      )
    {
        my $test = shift @$opts;
        note "test: $test\n";

        # Check for NPN/ALPN
        if ( !check_tls( @{ $opts->[0] } ) ) {
            note "skiped $test: feature not avaliable\n";
            next;
        }

        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm 5;
            test_tcp(
                client => sub {
                    my $port = shift;
                    client(
                        @{ $opts->[0] },
                        port     => $port,
                        host     => $host,
                        on_error => sub {
                            fail "error occured: " . shift;
                        },
                        test_cb => sub {
                            my $client = shift;
                            $client->request(
                                ':scheme'    => "http",
                                ':authority' => $host . ":" . $port,
                                ':path'      => "/",
                                ':method'    => "GET",
                                headers      => [
                                    'accept'     => '*/*',
                                    'user-agent' => 'perl-Protocol-HTTP2/'
                                      . $Protocol::HTTP2::VERSION,
                                ],
                                on_done => sub {
                                    my ( $headers, $data ) = @_;
                                    is scalar(@$headers) / 2, 6,
                                      "get response headers";
                                    is length($data), 13, "get body";
                                },
                            );
                        }
                    );
                },
                server => sub {
                    my $port = shift;
                    my $server;
                    server(
                        @{ $opts->[1] },
                        port     => $port,
                        host     => $host,
                        on_error => sub {
                            fail "error occured: " . shift;
                        },
                        test_cb => sub {
                            $server = shift;
                        },
                        on_request => sub {
                            my ( $stream_id, $headers, $data ) = @_;
                            my $message = "hello, world!";
                            $server->response(
                                ':status' => 200,
                                stream_id => $stream_id,
                                headers   => [
                                    'server' => 'perl-Protocol-HTTP2/'
                                      . $Protocol::HTTP2::VERSION,
                                    'content-length' => length($message),
                                    'cache-control'  => 'max-age=3600',
                                    'date' => 'Fri, 18 Apr 2014 07:27:11 GMT',
                                    'last-modified' =>
                                      'Thu, 27 Feb 2014 10:30:37 GMT',
                                ],
                                data => $message,
                            );
                        },
                    );
                },
            );
            alarm 0;
        };
        is $@, '', "no errors";
    }
};

done_testing;
