requires 'perl', '5.008001';
requires 'Log::Dispatch', 2.006;
requires 'Hash::MultiValue', 0.12;

on 'test' => sub {
    requires 'Test::More', '0.98';
};

on 'develop' => sub {
    requires 'XML::LibXML';
    requires 'AnyEvent';
};
