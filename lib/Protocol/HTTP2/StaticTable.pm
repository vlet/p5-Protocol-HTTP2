package Protocol::HTTP2::StaticTable;
use strict;
use warnings;
require Exporter;
our @ISA = qw(Exporter);
our ( @stable, %rstable );
our @EXPORT = qw(@stable %rstable);

@stable = (
    [ ":authority",                  "" ],
    [ ":method",                     "GET" ],
    [ ":method",                     "POST" ],
    [ ":path",                       "/" ],
    [ ":path",                       "/index.html" ],
    [ ":scheme",                     "http" ],
    [ ":scheme",                     "https" ],
    [ ":status",                     "200" ],
    [ ":status",                     "204" ],
    [ ":status",                     "206" ],
    [ ":status",                     "304" ],
    [ ":status",                     "400" ],
    [ ":status",                     "404" ],
    [ ":status",                     "500" ],
    [ "accept-charset",              "" ],
    [ "accept-encoding",             "gzip, deflate" ],
    [ "accept-language",             "" ],
    [ "accept-ranges",               "" ],
    [ "accept",                      "" ],
    [ "access-control-allow-origin", "" ],
    [ "age",                         "" ],
    [ "allow",                       "" ],
    [ "authorization",               "" ],
    [ "cache-control",               "" ],
    [ "content-disposition",         "" ],
    [ "content-encoding",            "" ],
    [ "content-language",            "" ],
    [ "content-length",              "" ],
    [ "content-location",            "" ],
    [ "content-range",               "" ],
    [ "content-type",                "" ],
    [ "cookie",                      "" ],
    [ "date",                        "" ],
    [ "etag",                        "" ],
    [ "expect",                      "" ],
    [ "expires",                     "" ],
    [ "from",                        "" ],
    [ "host",                        "" ],
    [ "if-match",                    "" ],
    [ "if-modified-since",           "" ],
    [ "if-none-match",               "" ],
    [ "if-range",                    "" ],
    [ "if-unmodified-since",         "" ],
    [ "last-modified",               "" ],
    [ "link",                        "" ],
    [ "location",                    "" ],
    [ "max-forwards",                "" ],
    [ "proxy-authenticate",          "" ],
    [ "proxy-authorization",         "" ],
    [ "range",                       "" ],
    [ "referer",                     "" ],
    [ "refresh",                     "" ],
    [ "retry-after",                 "" ],
    [ "server",                      "" ],
    [ "set-cookie",                  "" ],
    [ "strict-transport-security",   "" ],
    [ "transfer-encoding",           "" ],
    [ "user-agent",                  "" ],
    [ "vary",                        "" ],
    [ "via",                         "" ],
    [ "www-authenticate",            "" ],
);

for my $k ( 0 .. $#stable ) {
    my $key = join ' ', @{ $stable[$k] };
    $rstable{$key} = $k + 1;
    $rstable{ $stable[$k]->[0] . ' ' } = $k + 1
      if ( $stable[$k]->[1] ne ''
        && !exists $rstable{ $stable[$k]->[0] . ' ' } );
}

1;
