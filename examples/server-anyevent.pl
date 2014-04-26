use strict;
use warnings;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Protocol::HTTP2::Server;
use Protocol::HTTP2::Constants qw(const_name);

my $host = '127.0.0.1';
my $port = 8000;

my $w = AnyEvent->condvar;

tcp_server $host, $port, sub {
    my ( $fh, $host, $port ) = @_;
    my $handle;
    $handle = AnyEvent::Handle->new(
        fh       => $fh,
        autocork => 1,
        on_error => sub {
            $_[0]->destroy;
            print "connection error\n";
        },
        on_eof => sub {
            $handle->destroy;
        }
    );

    my $server;
    $server = Protocol::HTTP2::Server->new(
        on_change_state => sub {
            my ( $stream_id, $previous_state, $current_state ) = @_;
            printf "Stream %i changed state from %s to %s\n",
              $stream_id, const_name( "states", $previous_state ),
              const_name( "states", $current_state );
        },
        on_error => sub {
            my $error = shift;
            printf "Error occured: %s\n", const_name( "errors", $error );
        },
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;
            my $message = "hello, world!";
            $server->response(
                ':status' => 200,
                stream_id => $stream_id,
                headers   => [
                    'server'         => 'perl-Protocol-HTTP2/0.01',
                    'content-length' => length($message),
                    'cache-control'  => 'max-age=3600',
                    'date'           => 'Fri, 18 Apr 2014 07:27:11 GMT',
                    'last-modified'  => 'Thu, 27 Feb 2014 10:30:37 GMT',
                ],
                data => $message,
            );
        },
    );

    # First send settings to peer
    while ( my $frame = $server->next_frame ) {
        $handle->push_write($frame);
    }

    $handle->on_read(
        sub {
            my $handle = shift;

            $server->feed( $handle->{rbuf} );

            $handle->{rbuf} = undef;
            while ( my $frame = $server->next_frame ) {
                $handle->push_write($frame);
            }
            $handle->push_shutdown if $server->shutdown;
        }
    );
};

$w->recv;

