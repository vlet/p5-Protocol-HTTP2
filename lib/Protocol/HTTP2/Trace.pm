package Protocol::HTTP2::Trace;
use strict;
use warnings;
use Protocol::HTTP2::Constants qw(:flags :errors);
use Log::Dispatch;

use Exporter qw(import);
our @EXPORT_OK = qw(tracer bin2hex);

my $level = ( exists $ENV{HTTP2_DEBUG} ) ? $ENV{HTTP2_DEBUG} : 'critical';

my $tracer_sngl =
  Log::Dispatch->new( outputs => [ [ 'Screen', min_level => $level ], ], );

sub tracer {
    $tracer_sngl;
}

sub bin2hex {
    my $bin = shift;
    my $c   = 0;
    my $s;

    join "", map {
        $c++;
        $s = !( $c % 16 ) ? "\n" : ( $c % 2 ) ? "" : " ";
        $_ . $s
    } unpack( "(H2)*", $bin );

}

1;
