use strict;
use warnings;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Net::SSLeay;
use AnyEvent::TLS;

use Protocol::HTTP2;
use Protocol::HTTP2::Server;
use Protocol::HTTP2::Constants qw(const_name);

Net::SSLeay::initialize();

my $host = '127.0.0.1';
my $port = 8000;

my $w = AnyEvent->condvar;

tcp_server $host, $port, sub {
    my ( $fh, $host, $port ) = @_;
    my $handle;

    my $tls;
    eval {
        $tls = AnyEvent::TLS->new(
            method    => "TLSv1_2",
            cert_file => "test.crt",
            key_file  => "test.key",
        );

        # ECDH curve ( Net-SSLeay >= 1.56, openssl >= 1.0.0 )
        if ( exists &Net::SSLeay::CTX_set_tmp_ecdh ) {
            my $curve = Net::SSLeay::OBJ_txt2nid('prime256v1');
            my $ecdh  = Net::SSLeay::EC_KEY_new_by_curve_name($curve);
            Net::SSLeay::CTX_set_tmp_ecdh( $tls->ctx, $ecdh );
            Net::SSLeay::EC_KEY_free($ecdh);
        }

        # ALPN (Net-SSLeay > 1.55, openssl >= 1.0.2)
        if ( exists &Net::SSLeay::CTX_set_alpn_select_cb ) {
            Net::SSLeay::CTX_set_alpn_select_cb( $tls->ctx,
                [Protocol::HTTP2::ident_tls] );
        }

        # NPN  (Net-SSLeay > 1.45, openssl >= 1.0.1)
        elsif ( exists &Net::SSLeay::CTX_set_next_protos_advertised_cb ) {
            Net::SSLeay::CTX_set_next_protos_advertised_cb( $tls->ctx,
                [Protocol::HTTP2::ident_tls] );
        }
        else {
            die "ALPN and NPN is not supported\n";
        }
    };

    if ($@) {
        print "Some problem with SSL CTX: $@\n";
        $w->send;
        return;
    }

    $handle = AnyEvent::Handle->new(
        fh       => $fh,
        autocork => 1,
        tls      => "accept",
        tls_ctx  => $tls,
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
            printf "Error occurred: %s\n", const_name( "errors", $error );
        },
        on_request => sub {
            my ( $stream_id, $headers, $data ) = @_;
            my %h = (@$headers);

            # Push promise (must be before response)
            if ( $h{':path'} eq '/minil.toml' ) {
                $server->push(
                    ':authority' => $host . ':' . $port,
                    ':method'    => 'GET',
                    ':path'      => '/css/style.css',
                    ':scheme'    => 'https',
                    stream_id    => $stream_id,
                );
            }

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
