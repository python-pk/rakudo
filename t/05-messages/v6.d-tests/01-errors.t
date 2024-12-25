use Test;

plan 1;


throws-like { await 42 }, Exception, 'giving await non-Awaitable things throws';

# vim: expandtab shiftwidth=4
