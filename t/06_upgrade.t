use strict;
use warnings;
use Test::More;
use Protocol::HTTP2::Constants qw(const_name :endpoints :states);

BEGIN {
    use_ok('Protocol::HTTP2::Connection');
}

subtest 'decode_upgrade_response' => sub {

    my $con = Protocol::HTTP2::Connection->new(CLIENT);

    my $buf = join "\x0d\x0a",
      "\x00HTTP/1.1 101 Switching Protocols",
      "Connection: Upgrade",
      "SomeHeader: bla bla",
      "Upgrade: h2c-16", "",
      "here is some binary data";
    is $con->decode_upgrade_response( \$buf, 1 ), 95, "correct pos";

    $buf =~ s/101/200/;
    is $con->decode_upgrade_response( \$buf, 1 ), undef, "no switch";
    $buf =~ s/200/101/;

    $buf =~ s/h2c/xyz/;
    is $con->decode_upgrade_response( \$buf, 1 ), undef,
      "wrong Upgrade protocol";
    $buf =~ s/xyz/h2c/;

    is $con->decode_upgrade_response( \substr( $buf, 0, 80 ), 1 ), 0,
      "wait another portion of data\n";
};

subtest 'decode_upgrade_request' => sub {

    my $con = Protocol::HTTP2::Connection->new(SERVER);

    my $buf = join "\x0d\x0a",
      "\x00GET /default.htm HTTP/1.1",
      "Host: server.example.com",
      "Connection: Upgrade, HTTP2-Settings",
      "Upgrade: h2c-16",
      "HTTP2-Settings: AAAABAAAAAAA",
      "User-Agent: perl-Protocol-HTTP2/0.10",
      "", "";

    is $con->decode_upgrade_request( \$buf, 1 ), length($buf) - 1,
      "correct pos";

};

done_testing;
