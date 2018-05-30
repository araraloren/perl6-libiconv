use Test;
use IConv;

plan 1;

my buf8 $buf1 .= new(< 7b 0a 20 20 20 20 22 70 65 72 >.map({ .parse-base(16) }));

my buf8 $buf2 = iconv($buf1, from => "utf8", to => "utf32le");

my buf8 $buf3 = iconv($buf2, from => "utf32le", to => "utf8");

is $buf3, $buf1, "call sub iconv ok.";