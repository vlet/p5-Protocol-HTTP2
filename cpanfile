requires 'perl', '5.008001';
requires 'Log::Dispatch', 2.006;
requires 'Hash::MultiValue', 0.12;

# DATA frames requires gzip (since draft 12)
requires 'IO::Compress', 2.033;

on 'test' => sub {
    requires 'Test::More', '0.98';
};

on 'develop' => sub {
    requires 'XML::LibXML';
    requires 'AnyEvent';
};
