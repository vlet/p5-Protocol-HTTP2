package Protocol::HTTP2;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.01";

our $draft = "11";

sub ident_plain {
    'h2c-' . $draft;
}

sub ident_tls {
    'h2-' . $draft;
}

1;
__END__

=encoding utf-8

=head1 NAME

Protocol::HTTP2 - HTTP2 protocol (draft 11) implementation

=head1 SYNOPSIS

    use Protocol::HTTP2;

=head1 DESCRIPTION

Protocol::HTTP2 is HTTP2 protocol (draft 11) implementation.

=head1 LICENSE

Copyright (C) Vladimir Lettiev.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Vladimir Lettiev E<lt>crux@cpan.orgE<gt>

=cut

