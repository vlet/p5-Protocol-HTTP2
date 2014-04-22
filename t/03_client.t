use strict;
use warnings;
use Test::More;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

BEGIN { use_ok('Protocol::HTTP2::Client') }

my $client = Protocol::HTTP2::Client(
    on_change_state => sub {
        my ( $current_state, $previous_state ) = @_;
        print "Changed state to $current_state from $previous_state\n";
    },
);

my $host = '127.0.0.1';
my $port = 8000;

my $request = $client->request(
    ':scheme'   => "http",
    ':autority' => $host . ":",
    $port,
    ':path'   => "/LICENSE",
    ':method' => "GET",
    headers   => [ 'host' => $host ],
    on_done   => sub {
        my $data = shift;
        printf "Get data. Length: %i\n", length($data);
    },
    on_error => sub {
        my ( $status, $error ) = @_;
        printf "Error occured %s: %s\n", $status, $error;
    }
);

my $w = AnyEvent->condvar;

tcp_connect $host, $port, sub {
    my ($fh) = @_ or die "connection failed: $!";
    my $handle;
    $handle = AnyEvent::Handle->new(
        fh       => $fh,
        on_error => sub {
            $_[0]->destroy;
            $w->send;
        },
        on_eof => sub {
            $handle->destroy;
            $w->send;
        }
    );

    $handle->push_write( $client->preface );

    $handle->on_read(
        sub {
            my $handle = shift;

            $client->feed( $handle->{rbuf} );

            $handle->{rbuf} = undef;
            while ( my $data = $client->data ) {
                $handle->push_write($data);
            }

        }
    );
};

$w->recv;

done_testing;
