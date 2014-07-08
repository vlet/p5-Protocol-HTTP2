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
my $hufftable =
  XML::LibXML::XPathExpression->new(
    '//section[@title="Huffman Code"]//artwork');
my $value = $doc->findvalue($hufftable);
die "cant find Huffman Codes section" unless $value;

print << 'EOF';
package Protocol::HTTP2::HuffmanCodes;
use strict;
use warnings;
require Exporter;
our @ISA = qw(Exporter);
our ( %hcodes, %rhcodes, $hre );
our @EXPORT = qw(%hcodes %rhcodes $hre);

%hcodes = (
EOF

for ( split /\n/, $value ) {
    my ( $code, $hex, $bit ) = (/\((.{3})\).+\s([0-9a-f]+)\s+\[\s*(\d+)\]/)
      or next;
    printf "    %3d => '%0${bit}b',\n", $code, hex($hex);
}

print << 'EOF';
);

%rhcodes = reverse %hcodes;

{
    local $" = '|';
    $hre = qr/(?:^|\G)(@{[ keys %rhcodes ]})/;
}

1;
EOF

