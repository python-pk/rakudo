use Test;

plan 6;


is-deeply +combinations(100, 70), 29372339821610944823963760,
  'combinations() iterator implements efficient .count-only';
is-deeply ?combinations(100, 70), True,
  'combinations() iterator implements efficient .bool-only';

is-deeply +permutations(20), 2432902008176640000,
  '&permutations() iterator implements efficient .count-only';
is-deeply ?permutations(20), True,
  '&permutations() iterator implements efficient .bool-only';


is-deeply  ^20 .permutations.elems, 2432902008176640000,
  '.permutations() iterator implements efficient .count-only';
is-deeply  ^20 .permutations.so, True,
  '.permutations() iterator implements efficient .bool-only';

# vim: expandtab shiftwidth=4
