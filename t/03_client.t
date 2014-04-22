use strict;
use warnings;
use Test::More;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

BEGIN { use_ok('Protocol::HTTP2::Client') }

my $client = Protocol::HTTP2::Client->new(
    on_change_state => sub {
        my ( $current_state, $previous_state ) = @_;
        print "Changed state to $current_state from $previous_state\n";
    },
    on_error => sub {
        my ( $status, $error ) = @_;
        printf "Error occured %s: %s\n", $status, $error;
    }
);

my $host = '127.0.0.1';
my $port = 8000;

$client->request(
    ':scheme'    => "http",
    ':authority' => $host . ":" . $port,
    ':path'      => "/minil.toml",
    ':method'    => "GET",
    headers      => [
        [ 'accept'          => '*/*' ],
        [ 'accept-encoding' => 'gzip, deflate' ],
        [ 'user-agent'      => 'perl-Protocol-HTTP2/0.01' ],
    ],
    on_done => sub {
        my ( $headers, $data ) = shift;
        printf "Get headers. Count: %i\n", scalar @$headers % 2;
        printf "Get data. Length: %i\n",   length($data);
    },
);

my $w = AnyEvent->condvar;

tcp_connect $host, $port, sub {
    my ($fh) = @_ or die "connection failed: $!";
    my $handle;
    $handle = AnyEvent::Handle->new(
        fh       => $fh,
        autocork => 1,
        on_error => sub {
            $_[0]->destroy;
            print "connection error\n";
            $w->send;
        },
        on_eof => sub {
            $handle->destroy;
            print "just eof\n";
            $w->send;
        }
    );

    # First write to peer
    while ( my $data = $client->data ) {
        $handle->push_write($data);
    }

    $handle->on_read(
        sub {
            my $handle = shift;

            $client->feed( $handle->{rbuf} );

            $handle->{rbuf} = undef;
            while ( my $data = $client->data ) {
                $handle->push_write($data);
            }
            $handle->push_shutdown if $client->shutdown;
        }
    );
};

$w->recv;

done_testing;
