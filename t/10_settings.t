use strict;
use warnings;
use Test::More;
use lib 't/lib';
use PH2Test;
use Protocol::HTTP2::Constants qw(:settings);
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;

subtest 'client settings' => sub {

    my $c =
      Protocol::HTTP2::Client->new(
        settings => { &SETTINGS_HEADER_TABLE_SIZE => 100 } );
    $c->request(
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        ':method'    => 'GET',
    );

    # PRI
    $c->next_frame;

    # SETTINGS
    ok binary_eq( hstr('0000 0604 0000 0000 0000 0100 0000 64'),
        $c->next_frame ),
      "send only changed from default values settings";
};

subtest 'server settings' => sub {

    my $s = Protocol::HTTP2::Server->new;

    ok binary_eq( hstr('0000 0604 0000 0000 0000 0300 0000 64'),
        $s->next_frame ), "server defaults not empty";
};

done_testing;
