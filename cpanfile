requires 'perl', '5.008001';
requires 'Log::Dispatch', '2.006';

# (encode,decode)_base64url
requires 'MIME::Base64', '3.11';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'AnyEvent';
    requires 'Net::SSLeay', '> 1.45';
    requires 'Test::TCP';
};

on 'develop' => sub {
    requires 'XML::LibXML';
    requires 'AnyEvent';
    requires 'Net::SSLeay', '> 1.45';
};
