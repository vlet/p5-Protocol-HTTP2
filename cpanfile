requires 'perl', '5.008001';

# (encode,decode)_base64url
requires 'MIME::Base64', '3.11';

# weaken
requires 'Scalar::Util';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'AnyEvent';
    requires 'Net::SSLeay', '> 1.45';
    requires 'Test::TCP';
    requires 'Test::LeakTrace';
};

on 'develop' => sub {
    requires 'XML::LibXML';
    requires 'AnyEvent';
    requires 'Net::SSLeay', '> 1.45';
};
