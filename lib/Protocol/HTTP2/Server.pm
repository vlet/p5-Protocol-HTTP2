package Protocol::HTTP2::Server;
use strict;
use warnings;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states :endpoints
  :settings :limits const_name);
use Protocol::HTTP2::Trace qw(tracer);
use Carp;
use Scalar::Util ();

=encoding utf-8

=head1 NAME

Protocol::HTTP2::Server - HTTP/2 server

=head1 SYNOPSIS

    use Protocol::HTTP2::Server;

    # You must create tcp server yourself
    use AnyEvent;
    use AnyEvent::Socket;
    use AnyEvent::Handle;

    my $w = AnyEvent->condvar;

    # Plain-text HTTP/2 connection
    tcp_server 'localhost', 8000, sub {
        my ( $fh, $peer_host, $peer_port ) = @_;
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

        # Create Protocol::HTTP2::Server object
        my $server;
        $server = Protocol::HTTP2::Server->new(
            on_request => sub {
                my ( $stream_id, $headers, $data ) = @_;
                my $message = "hello, world!";

                # Response to client
                $server->response(
                    ':status' => 200,
                    stream_id => $stream_id,

                    # HTTP/1.1 Headers
                    headers   => [
                        'server'         => 'perl-Protocol-HTTP2/0.13',
                        'content-length' => length($message),
                        'cache-control'  => 'max-age=3600',
                        'date'           => 'Fri, 18 Apr 2014 07:27:11 GMT',
                        'last-modified'  => 'Thu, 27 Feb 2014 10:30:37 GMT',
                    ],

                    # Content
                    data => $message,
                );
            },
        );

        # First send settings to peer
        while ( my $frame = $server->next_frame ) {
            $handle->push_write($frame);
        }

        # Receive clients frames
        # Reply to client
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



=head1 DESCRIPTION

Protocol::HTTP2::Server is HTTP/2 server library. It's intended to make
http2-server implementations on top of your favorite event loop.

See also L<Shuvgey|https://github.com/vlet/Shuvgey> - AnyEvent HTTP/2 Server
for PSGI based on L<Protocol::HTTP2::Server>.

=head2 METHODS

=head3 new

Initialize new server object

    my $server = Protocol::HTTP2::Client->new( %options );

Available options:

=over

=item on_request => sub {...}

Callback invoked when receiving client's requests

    on_request => sub {
        # Stream ID, headers array reference and body of request
        my ( $stream_id, $headers, $data ) = @_;

        my $message = "hello, world!";
        $server->response(
            ':status' => 200,
            stream_id => $stream_id,
            headers   => [
                'server'         => 'perl-Protocol-HTTP2/0.13',
                'content-length' => length($message),
            ],
            data => $message,
        );
        ...
    },


=item upgrade => 0|1

Use HTTP/1.1 Upgrade to upgrade protocol from HTTP/1.1 to HTTP/2. Upgrade
possible only on plain (non-tls) connection.

See
L<Starting HTTP/2 for "http" URIs|https://tools.ietf.org/html/rfc7540#section-3.2>

=item on_error => sub {...}

Callback invoked on protocol errors

    on_error => sub {
        my $error = shift;
        ...
    },

=item on_change_state => sub {...}

Callback invoked every time when http/2 streams change their state.
See
L<Stream States|https://tools.ietf.org/html/rfc7540#section-5.1>

    on_change_state => sub {
        my ( $stream_id, $previous_state, $current_state ) = @_;
        ...
    },

=back

=cut

sub new {
    my ( $class, %opts ) = @_;
    my $self = {
        con      => undef,
        input    => '',
        settings => {
            &SETTINGS_MAX_CONCURRENT_STREAMS => DEFAULT_MAX_CONCURRENT_STREAMS,
            exists $opts{settings} ? %{ delete $opts{settings} } : ()
        },
    };
    if ( exists $opts{on_request} ) {
        Scalar::Util::weaken( my $self = $self );

        $self->{cb} = delete $opts{on_request};
        $opts{on_new_peer_stream} = sub {
            my $stream_id = shift;
            $self->{con}->stream_cb(
                $stream_id,
                HALF_CLOSED,
                sub {
                    $self->{cb}->(
                        $stream_id,
                        $self->{con}->stream_headers($stream_id),
                        $self->{con}->stream_data($stream_id),
                    );
                }
            );
          }
    }

    $self->{con} =
      Protocol::HTTP2::Connection->new( SERVER, %opts,
        settings => $self->{settings} );
    $self->{con}->enqueue( SETTINGS, 0, 0, $self->{settings} )
      unless $self->{con}->upgrade;

    bless $self, $class;
}

=head3 response

Prepare response

    my $message = "hello, world!";
    $server->response(

        # HTTP/2 status
        ':status' => 200,

        # Stream ID
        stream_id => $stream_id,

        # HTTP/1.1 headers
        headers   => [
            'server'         => 'perl-Protocol-HTTP2/0.01',
            'content-length' => length($message),
        ],

        # Body of response
        data => $message,
    );

=cut

my @must = (qw(:status));

sub response {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing headers in response: @miss" if @miss;

    my $con = $self->{con};

    $con->send_headers(
        $h{stream_id},
        [
            ( map { $_ => $h{$_} } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ],
        exists $h{data} ? 0 : 1
    );
    $con->send_data( $h{stream_id}, $h{data}, 1 ) if exists $h{data};
    return $self;
}

=head3 response_stream

If body of response is not yet ready or server will stream data

    # P::H::Server::Stream object
    my $server_stream;
    $server_stream = $server->response_stream(

        # HTTP/2 status
        ':status' => 200,

        # Stream ID
        stream_id => $stream_id,

        # HTTP/1.1 headers
        headers   => [
            'server'         => 'perl-Protocol-HTTP2/0.01',
        ],

        # Callback if client abort this stream
        on_cancel => sub {
            ...
        }
    );

    # Send partial data
    $server_stream->send($chunk_of_data);
    $server_stream->send($chunk_of_data);

    ## 3 ways to finish stream:
    #
    # The best: send last chunk and close stream in one action
    $server_stream->last($chunk_of_data);

    # Close the stream (will send empty frame)
    $server_stream->close();

    # Destroy object (will send empty frame)
    undef $server_stream

=cut

{

    package Protocol::HTTP2::Server::Stream;
    use Protocol::HTTP2::Constants qw(:states);
    use Scalar::Util ();

    sub new {
        my ( $class, %opts ) = @_;
        my $self = bless {%opts}, $class;

        if ( my $on_cancel = $self->{on_cancel} ) {
            Scalar::Util::weaken( my $self = $self );
            $self->{con}->stream_cb(
                $self->{stream_id},
                CLOSED,
                sub {
                    return if $self->{done};
                    $self->{done} = 1;
                    $on_cancel->();
                }
            );
        }

        $self;
    }

    sub send {
        my $self = shift;
        $self->{con}->send_data( $self->{stream_id}, shift );
    }

    sub last {
        my $self = shift;
        $self->{done} = 1;
        $self->{con}->send_data( $self->{stream_id}, shift, 1 );
    }

    sub close {
        my $self = shift;
        $self->{done} = 1;
        $self->{con}->send_data( $self->{stream_id}, undef, 1 );
    }

    sub DESTROY {
        my $self = shift;
        $self->{con}->send_data( $self->{stream_id}, undef, 1 )
          unless $self->{done} || !$self->{con};
    }
}

sub response_stream {
    my ( $self, %h ) = @_;
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing headers in response_stream: @miss" if @miss;

    my $con = $self->{con};

    $con->send_headers(
        $h{stream_id},
        [
            ( map { $_ => $h{$_} } @must ),
            exists $h{headers} ? @{ $h{headers} } : ()
        ],
        0
    );

    return Protocol::HTTP2::Server::Stream->new(
        con       => $con,
        stream_id => $h{stream_id},
        on_cancel => $h{on_cancel},
    );
}

=head3 push

Prepare Push Promise. See
L<Server Push|https://tools.ietf.org/html/rfc7540#section-8.2>

    # Example of push inside of on_request callback
    on_request => sub {
        my ( $stream_id, $headers, $data ) = @_;
        my %h = (@$headers);

        # Push promise (must be before response)
        if ( $h{':path'} eq '/index.html' ) {

            # index.html contain styles.css resource, so server can push
            # "/style.css" to client before it request it to increase speed
            # of loading of whole page
            $server->push(
                ':authority' => 'localhost:8000',
                ':method'    => 'GET',
                ':path'      => '/style.css',
                ':scheme'    => 'http',
                stream_id    => $stream_id,
            );
        }

        $server->response(...);
        ...
    }

=cut

my @must_pp = (qw(:authority :method :path :scheme));

sub push {
    my ( $self, %h ) = @_;
    my $con = $self->{con};
    my @miss = grep { !exists $h{$_} } @must_pp;
    croak "Missing headers in push promise: @miss" if @miss;
    croak "Can't push on my own stream. "
      . "Seems like a recursion in request callback."
      if $h{stream_id} % 2 == 0;

    my $promised_sid = $con->new_stream;
    $con->stream_promised_sid( $h{stream_id}, $promised_sid );

    my @headers = map { $_ => $h{$_} } @must_pp;

    $con->send_pp_headers( $h{stream_id}, $promised_sid, \@headers, );

    # send promised response after current stream is closed
    $con->stream_cb(
        $h{stream_id},
        CLOSED,
        sub {
            $self->{cb}->( $promised_sid, \@headers );
        }
    );

    return $self;
}

=head3 shutdown

Get connection status:

=over

=item 0 - active

=item 1 - closed (you can terminate connection)

=back

=cut

sub shutdown {
    shift->{con}->shutdown;
}

=head3 next_frame

get next frame to send over connection to client.
Returns:

=over

=item undef - on error

=item 0 - nothing to send

=item binary string - encoded frame

=back

    # Example
    while ( my $frame = $server->next_frame ) {
        syswrite $fh, $frame;
    }

=cut

sub next_frame {
    my $self  = shift;
    my $frame = $self->{con}->dequeue;
    if ($frame) {
        my ( $length, $type, $flags, $stream_id ) =
          $self->{con}->frame_header_decode( \$frame, 0 );
        tracer->debug(
            sprintf "Send one frame to a wire:"
              . " type(%s), length(%i), flags(%08b), sid(%i)\n",
            const_name( 'frame_types', $type ), $length, $flags, $stream_id
        );
    }
    return $frame;
}

=head3 feed

Feed decoder with chunks of client's request

    sysread $fh, $binary_data, 4096;
    $server->feed($binary_data);

=cut

sub feed {
    my ( $self, $chunk ) = @_;
    $self->{input} .= $chunk;
    my $offset = 0;
    my $con    = $self->{con};
    tracer->debug( "got " . length($chunk) . " bytes on a wire\n" );

    if ( $con->upgrade ) {
        my @headers;
        my $len =
          $con->decode_upgrade_request( \$self->{input}, $offset, \@headers );
        $con->shutdown(1) unless defined $len;
        return unless $len;

        substr( $self->{input}, $offset, $len ) = '';

        $con->enqueue_raw( $con->upgrade_response );
        $con->enqueue( SETTINGS, 0, 0,
            {
                &SETTINGS_MAX_CONCURRENT_STREAMS =>
                  DEFAULT_MAX_CONCURRENT_STREAMS
            }
        );
        $con->upgrade(0);

        # The HTTP/1.1 request that is sent prior to upgrade is assigned stream
        # identifier 1 and is assigned default priority values (Section 5.3.5).
        # Stream 1 is implicitly half closed from the client toward the server,
        # since the request is completed as an HTTP/1.1 request.  After
        # commencing the HTTP/2 connection, stream 1 is used for the response.

        $con->new_peer_stream(1);
        $con->stream_headers( 1, \@headers );
        $con->stream_state( 1, HALF_CLOSED );
    }

    if ( !$con->preface ) {
        my $len = $con->preface_decode( \$self->{input}, $offset );
        unless ( defined $len ) {
            tracer->error("invalid preface. shutdown connection\n");
            $con->shutdown(1);
        }
        return unless $len;
        tracer->debug("got preface\n");
        $offset += $len;
        $con->preface(1);
    }

    while ( my $len = $con->frame_decode( \$self->{input}, $offset ) ) {
        tracer->debug("decoded frame at $offset, length $len\n");
        $offset += $len;
    }
    substr( $self->{input}, 0, $offset ) = '' if $offset;
}

=head3 ping

Send ping frame to client (to keep connection alive)

    $server->ping

or

    $server->ping($payload);

Payload can be arbitrary binary string and must contain 8 octets. If payload argument
is omitted server will send random data.

=cut

sub ping {
    shift->{con}->send_ping(@_);
}

1;
