package PH2ClientServerTest;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Net::SSLeay;
use AnyEvent::TLS;

use Protocol::HTTP2;
use Protocol::HTTP2::Client;
use Protocol::HTTP2::Server;
use Protocol::HTTP2::Constants qw(const_name);

use Exporter qw(import);
our @EXPORT = qw(client server check_tls);
use Carp;

sub check_tls {
    my (%opts) = @_;
    return
        exists $opts{npn}  ? exists &Net::SSLeay::P_next_proto_negotiated
      : exists $opts{alpn} ? exists &Net::SSLeay::P_alpn_selected
      :                      1;
}

sub server {
    my (%h) = @_;

    my $cb   = delete $h{test_cb} or croak "no servers test_cb";
    my $port = delete $h{port}    or croak "no port available";
    my $host = delete $h{host};
    my $tls_crt = delete $h{"tls_crt"};
    my $tls_key = delete $h{"tls_key"};

    my $w = AnyEvent->condvar;

    tcp_server $host, $port, sub {
        my ( $fh, $host, $port ) = @_;
        my $handle;
        my $tls;

        if ( !$h{upgrade} && ( $h{npn} || $h{alpn} ) ) {
            eval {
                $tls = AnyEvent::TLS->new(
                    method    => 'tlsv1',
                    cert_file => $tls_crt,
                    key_file  => $tls_key,
                );

                if ( $h{npn} ) {

                    # NPN  (Net-SSLeay > 1.45, openssl >= 1.0.1)
                    Net::SSLeay::CTX_set_next_protos_advertised_cb( $tls->ctx,
                        [Protocol::HTTP2::ident_tls] );
                }
                if ( $h{alpn} ) {

                    # ALPN (Net-SSLeay > 1.55, openssl >= 1.0.2)
                    Net::SSLeay::CTX_set_alpn_select_cb( $tls->ctx,
                        [Protocol::HTTP2::ident_tls] );
                }
            };
            if ($@) {
                croak "Some problem with SSL CTX: $@" . Net::SSLeay::print_errs();
            }
        }

        $handle = AnyEvent::Handle->new(
            fh       => $fh,
            autocork => 1,
            defined $tls
            ? (
                tls     => "accept",
                tls_ctx => $tls
              )
            : (),
            on_error => sub {
                $_[0]->destroy;
                print "connection error\n";
            },
            on_eof => sub {
                $handle->destroy;
            }
        );

        my $server = Protocol::HTTP2::Server->new(%h);
        $cb->($server);

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
    my $res = $w->recv;
    croak("error occurred\n") unless $res;
}

sub client {
    my (%h) = @_;
    my $port = delete $h{port} or croak "no port available";
    my $tls;

    my $host = delete $h{host};

    if ( delete $h{upgrade} ) {
        $h{upgrade} = 1;
    }
    elsif ( $h{npn} || $h{alpn} ) {
        eval {
            $tls = AnyEvent::TLS->new( method => 'tlsv1', );

            if ( delete $h{npn} ) {

                # NPN  (Net-SSLeay > 1.45, openssl >= 1.0.1)
                Net::SSLeay::CTX_set_next_proto_select_cb( $tls->ctx,
                    [Protocol::HTTP2::ident_tls] );
            }
            if ( delete $h{alpn} ) {

                # ALPN (Net-SSLeay > 1.55, openssl >= 1.0.2)
                Net::SSLeay::CTX_set_alpn_protos( $tls->ctx,
                    [Protocol::HTTP2::ident_tls] );
            }
        };
        if ($@) {
            croak "Some problem with SSL CTX: $@\n";
        }
    }

    my $cb = delete $h{test_cb} or croak "no clients test_cb";

    my $client = Protocol::HTTP2::Client->new(%h);
    $cb->($client);

    my $w = AnyEvent->condvar;

    tcp_connect $host, $port, sub {
        my ($fh) = @_ or do {
            print "connection failed: $!\n";
            $w->send(0);
            return;
        };

        my $handle;
        $handle = AnyEvent::Handle->new(
            fh => $fh,
            defined $tls
            ? (
                tls     => "connect",
                tls_ctx => $tls,
              )
            : (),
            autocork => 1,
            on_error => sub {
                $_[0]->destroy;
                print "connection error\n";
                $w->send(0);
            },
            on_eof => sub {
                $handle->destroy;
                $w->send(1);
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

    my $res = $w->recv;
    croak("error occurred\n") unless $res;
}

1;
