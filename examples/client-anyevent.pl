use strict;
use warnings;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Protocol::HTTP2::Client;
use Protocol::HTTP2::Constants qw(const_name);

my $client = Protocol::HTTP2::Client->new(
    on_change_state => sub {
        my ( $stream_id, $previous_state, $current_state ) = @_;
        printf "Stream %i changed state from %s to %s\n",
          $stream_id, const_name( "states", $previous_state ),
          const_name( "states", $current_state );
    },
    on_error => sub {
        my $error = shift;
        printf "Error occured: %s\n", const_name( "errors", $error );
    }
);

my $host = '127.0.0.1';
my $port = 8000;

# Prepare http/2 request
$client->request(
    ':scheme'    => "http",
    ':authority' => $host . ":" . $port,
    ':path'      => "/minil.toml",
    ':method'    => "GET",
    headers      => [
        'accept'     => '*/*',
        'user-agent' => 'perl-Protocol-HTTP2/0.01',
    ],
    on_done => sub {
        my ( $headers, $data ) = @_;
        printf "Get headers. Count: %i\n", scalar(@$headers) / 2;
        printf "Get data.   Length: %i\n", length($data);
        print $data;
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
            $w->send;
        }
    );

    # First write preface to peer
    while ( my $frame = $client->next_frame ) {
        $handle->push_write($frame);
    }

    $handle->on_read(
        sub {
            my $handle = shift;

            $client->feed( $handle->{rbuf} );

            $handle->{rbuf} = undef;
            while ( my $frame = $client->next_frame ) {
                $handle->push_write($frame);
            }
            $handle->push_shutdown if $client->shutdown;
        }
    );
};

$w->recv;

