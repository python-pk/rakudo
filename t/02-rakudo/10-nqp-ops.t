use lib <t/packages/Test-Helpers>;
use Test;
use Test::Helpers;
use nqp;
# Tests for nqp ops that don't fit into nqp's test suit

plan 2;


todo 'org.raku.nqp.sixmodel.reprs.P6OpaqueBaseInstance$BadReferenceRuntimeException: Cannot access a native attribute as a reference attribute',
    1, if $*VM eq 'jvm';
lives-ok {
    nqp::p6bindattrinvres(($ := 42), Int, q|$!value|, nqp::getattr(42, Int, q|$!value|))
}, 'p6bindattrinvres with getattr of bigint does not crash';


is-run ｢use nqp; quietly print nqp::getlexdyn('&DEPRECATED'); print 'pass'｣,
    :out<pass>, 'getlexdyn op does not segfault';

# vim: expandtab shiftwidth=4
