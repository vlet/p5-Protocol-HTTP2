package Protocol::HTTP2::Trace;
use strict;
use warnings;
use Time::HiRes qw(time);

use Exporter qw(import);
our @EXPORT_OK = qw(tracer bin2hex);

my %levels = (
    debug     => 0,
    info      => 1,
    notice    => 2,
    warning   => 3,
    error     => 4,
    critical  => 5,
    alert     => 6,
    emergency => 7,
);

my $tracer_sngl = Protocol::HTTP2::Trace->_new(
    min_level =>
      ( exists $ENV{HTTP2_DEBUG} && exists $levels{ $ENV{HTTP2_DEBUG} } )
    ? $levels{ $ENV{HTTP2_DEBUG} }
    : $levels{error}
);
my $start_time = 0;

sub tracer {
    $tracer_sngl;
}

sub _new {
    my ( $class, %opts ) = @_;
    bless {%opts}, $class;
}

sub _log {
    my ( $self, $level, $message ) = @_;
    $level = uc($level);
    chomp($message);
    my $now = time;
    if ( $now - $start_time < 60 ) {
        $message =~ s/\n/\n           /g;
        printf "[%05.3f] %s %s\n", $now - $start_time, $level, $message;
    }
    else {
        my @t = ( localtime() )[ 5, 4, 3, 2, 1, 0 ];
        $t[0] += 1900;
        $t[1]++;
        $message =~ s/\n/\n                      /g;
        printf "[%4d-%02d-%02d %02d:%02d:%02d] %s %s\n", @t, $level, $message;
        $start_time = $now;
    }
}

{
    no strict 'refs';
    for my $l ( keys %levels ) {
        *{ __PACKAGE__ . "::" . $l } =
          ( $levels{$l} >= $tracer_sngl->{min_level} )
          ? sub {
            shift->_log( $l, @_ );
          }
          : sub { 1 }
    }
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
