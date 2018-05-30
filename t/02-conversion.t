#!/usr/bin/env perl6

use Test;
use IConv;

plan 3;

my IConv $iconv .= new(from => 'utf8', to => 'utf16le');

my buf8 $buf .= new(< 7b 0a 20 20 20 20 22 70 65 72 >.map({ .parse-base(16) }));

my $ret = $iconv($buf);

is $ret, buf8.new(<7b 00 0a 00 20 00 20 00 20 00 20 00 22 00 70 00 65 00 72 00>.map({ .parse-base(16) })), "convert to utf16le okay";

is $iconv.errno-of-c, 0, "errno is 0";

$iconv.reset;

lives-ok {
    $iconv.close;
}, "close ok";