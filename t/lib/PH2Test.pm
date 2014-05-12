package PH2Test;
use strict;
use warnings;
use Protocol::HTTP2::Trace qw(bin2hex);
use Exporter qw(import);
our @EXPORT = qw(hstr binary_eq);

sub hstr {
    my $str = shift;
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

1;
