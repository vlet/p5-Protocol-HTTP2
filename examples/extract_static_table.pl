#!/usr/bin/perl
#
use strict;
use warnings;

use XML::LibXML;

sub usage {
    "Usage: $0 draft-ietf-httpbis-header-compression.xml\n";
}

my $file = $ARGV[0] or die usage;
die usage unless -f $file;

open my $fh, '<', $file or die $!;
my $doc = XML::LibXML->load_xml( IO => $fh );
my $stattable =
  XML::LibXML::XPathExpression->new(
    '//texttable[@title="Static Table Entries"]/c');
my @nodes = $doc->findnodes($stattable);

print <<'EOF';
package Protocol::HTTP2::StaticTable;
use strict;
use warnings;
require Exporter;
our @ISA = qw(Exporter);
our (%stable, %rstable);
our @EXPORT = qw(%stable %rstable);

%stable = (
EOF

while (@nodes) {
    my ( $idx, $name, $value ) = map { $_->textContent } splice( @nodes, 0, 3 );
    last unless $idx;
    printf qq{    %2d => [ "%s", "%s" ],\n}, $idx, $name, $value;
}

print <<'EOF';
);

for my $k (keys %stable) {
    my $key = join ' ', @{ $stable{$k} };
    $rstable{$key} = $k;
}

1;
EOF

