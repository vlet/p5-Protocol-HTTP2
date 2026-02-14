package PH2Test;
use strict;
use warnings;
use Protocol::HTTP2::Trace qw(bin2hex);
use Exporter qw(import);
our @EXPORT = qw(hstr binary_eq fake_connect random_string);

sub hstr {
    my $str = shift;
    $str =~ s/\#.*//g;
    $str =~ s/\s//g;
    my @a = ( $str =~ /../g );
    return pack "C*", map { hex $_ } @a;
}

sub binary_eq {
    my ( $b1, $b2 ) = @_;
    if ( $b1 eq $b2 ) {
        return 1;
    }
    else {
        $b1 = bin2hex($b1);
        $b2 = bin2hex($b2);
        chomp $b1;
        chomp $b2;
        print "$b1\n not equal \n$b2 \n";
        return 0;
    }
}

sub fake_connect {
    my ( $server, $client ) = @_;

    my ( $clt_frame, $srv_frame );
    do {
        $clt_frame = $client->next_frame;
        $srv_frame = $server->next_frame;
        $server->feed($clt_frame) if $clt_frame;
        $client->feed($srv_frame) if $srv_frame;
    } while ( $clt_frame || $srv_frame );
}

sub random_string {
    my @chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
    join '', map { $chars[ int( rand(@chars) ) ] } 1 .. shift;
}

1;
