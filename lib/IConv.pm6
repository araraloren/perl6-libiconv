use NativeCall;

my $errno := cglobal('libc.so.6', 'errno', int32);

class EncodeBuf { ... }

class X::IConv::Error is Exception is export {
    has $.errno;
    has $.message = "Invalid multibyte sequence!";
}

constant libiconv   = Str;
constant E2BIG      = 7;
constant EILSEQ     = 84;
constant EINVAL     = 22;

class IConv is repr('CPointer') is export {

    sub iconv_open(Str $to, Str $from --> IConv) is native(libiconv) { * }

    method new(Str :$to!, Str :$from!) {
        my $cd = iconv_open($to, $from);
        if nativecast(Pointer[void], $cd) == Pointer[void].new(-1) {
            X::IConv::Error.new(
                message => do {
                    given $errno {
                        when EINVAL {
                            "Not support coversion from {$from} to {$to}!";
                        }
                        default {
                            "Call icon_open failed!";
                        }
                    }
                },
                errno => $errno,
            ).throw;
        }
        return $cd;
    }

    sub iconv(IConv, CArray[CArray[uint8]], size_t is rw, CArray[CArray[uint8]], size_t is rw --> size_t) is native(libiconv) { * }

    sub process-return-of-iconv(int32 $ret) {
        if $ret == int32ToSizet(-1) && $errno != E2BIG {
            X::IConv::Error.new(
                message => do {
                    given $errno {
                        when EILSEQ {
                            "An invalid multibyte sequence has been encoutered!"
                        }
                        when EINVAL {
                            "An incomplete multibyte sequence has been encoutered!"
                        }
                        default {
                            "Convert failed!";
                        }
                    }
                },
                errno => $errno,
            ).throw;
        }
    }

    method CALL-ME(buf8:D $buf, :$size = 512 --> buf8) {
        my CArray[CArray[uint8]] $sptr .= new();
        my size_t $inleft = $buf.elems;
        my EncodeBuf @bufs;

        $sptr[0] = nativecast(CArray[uint8], $buf);
        while $inleft > 0 {
            @bufs.push(my $eb := EncodeBuf.new($size));
            process-return-of-iconv(
                iconv(self, $sptr, $inleft, $eb.get-double-ptr(), $eb.left())
            );
        }
        return mergeEncodeBuf(@bufs);
    }

    method reset() {
        my size_t $t = 0;
        process-return-of-iconv(
            iconv(self, CArray[CArray[uint8]], $t, CArray[CArray[uint8]], $t)
        );
    }

    #`( maybe we should not support non-standard function
    sub iconvctl(IConv, int32, int32 is rw --> int32) is native(libiconv) { * }

    sub process-return-of-ctl(int32 $ret) {
        if $ret == -1 {
            X::IConv::Error.new(
                message => do {
                    given $errno {
                        when EINVAL {
                            "The request is invalid!"
                        }
                        default {
                            "Call iconvctl failed!";
                        }
                    }
                },
                errno => $errno,
            ).throw;
        }
    }

    constant ICONV_TRIVIAL = 0;
    constant ICONV_GET_TRANSLITERATE = 1;
    constant ICONV_SET_TRANSLITERATE = 2;
    constant ICONV_GET_DISCARD_ILSEQ = 3;
    constant ICONV_SET_DISCARD_ILSEQ = 4;

    method is-trivial(--> Bool) {
        my int32 $v = -1;
        process-return-of-ctl( iconvctl(self, ICONV_TRIVIAL, $v) );
        ?$v;
    }

    method translterate() is rw {
        my \SELF = self;
        my int32 $v = -1;
        Proxy.new(
            FETCH => method () {
                process-return-of-ctl( iconvctl(SELF, ICONV_GET_TRANSLITERATE, $v) );
                ?$v;
            },
            STORE => method (Bool $boolean) {
                $v = 0 unless $boolean;
                process-return-of-ctl( iconvctl(SELF, ICONV_SET_TRANSLITERATE, $v) );
            }
        );
    }

    method discard-ilseq() is rw {
        my \SELF = self;
        my int32 $v = -1;
        Proxy.new(
            FETCH => method () {
                process-return-of-ctl( iconvctl(SELF, ICONV_GET_DISCARD_ILSEQ, $v) );
                ?$v;
            },
            STORE => method (Bool $boolean) {
                $v = 0 unless $boolean;
                process-return-of-ctl( iconvctl(SELF, ICONV_SET_DISCARD_ILSEQ, $v) );
            }
        );
    })

    method errno-of-c() {
        $errno;
    }

    sub iconv_close(IConv --> int32) is native(libiconv) { * }

    method close() {
        if iconv_close(self) == -1 {
            X::IConv::Error.new(
                message => "Close iconv conversion descriptor failed!",
                errno => $errno,
            ).throw;
        }
    }
}

class EncodeBuf {
    has buf8    $.buf;
    has size_t  $.left;

    method new(size_t $size) {
        self.bless(buf => buf8.new(1 xx $size), left => $size);
    }

    method get-double-ptr() {
        my $c = CArray[CArray[uint8]].new();
        $c[0] = nativecast(CArray[uint8], $!buf);
        $c;
    }

    method size() {
        $!buf.elems - $!left;
    }

    method left() is rw {
        $!left;
    }

    method realbuf() {
        $!buf.subbuf(0 ..^ self.size());
    }
}

sub mergeEncodeBuf(@bufs --> buf8) {
    my buf8 $out;
    my ($all, $curr) = (0, 0);

    $all += .size() for @bufs;
    $out = buf8.new(^$all);

    for @bufs -> $buf {
        $out.subbuf-rw($curr) = $buf.realbuf();
        $curr += $buf.size();
    }
    $out;
}

sub int32ToSizet(int32 $from) {
    my CArray[int32] $c .= new($from);
    nativecast(Pointer[size_t], $c).deref;
}

sub iconv(buf8 $buf, :$size = 1024, :$from!, :$to! --> buf8) is export {
    my IConv $iconv .= new(:$from, :$to);
    my $ret = $iconv($buf, :$size);
    $iconv.close();
    $ret;
}