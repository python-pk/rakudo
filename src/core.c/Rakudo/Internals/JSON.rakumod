my class JSONException is Exception {
    has $.text;

    method message {
        'Invalid JSON: ' ~ $!text
    }
}

# A slightly modified version of https://github.com/timo/json_fast/blob/5ce76c039dc143fa9a068f1dfa47b42e58046821/lib/JSON/Fast.pm6
# Key differences:
#  - to-json stringifies Version objects
#  - Removes $*JSON_NAN_INF_SUPPORT and the Falsey code path(s) that use it
#  - Custom code for stringifying some exception related things
my class Rakudo::Internals::JSON {

    my multi sub to-surrogate-pair(Int $ord) {
        my int $base   = $ord - 0x10000;
        my int $top    = $base +& 0b1_1111_1111_1100_0000_0000 +> 10;
        my int $bottom = $base +&               0b11_1111_1111;
        Q/\u/ ~ (0xD800 + $top).base(16) ~ Q/\u/ ~ (0xDC00 + $bottom).base(16);
    }

    my multi sub to-surrogate-pair(Str $input) {
        to-surrogate-pair(nqp::ordat($input, 0));
    }



    my $tab := nqp::list_i(92,116); # \t
    my $lf  := nqp::list_i(92,110); # \n
    my $cr  := nqp::list_i(92,114); # \r
    my $qq  := nqp::list_i(92, 34); # \"
    my $bs  := nqp::list_i(92, 92); # \\

    # Convert string to decomposed codepoints.  Run over that integer array
    # and inject whatever is necessary, don't do anything if simple ascii.
    # Then convert back to string and return that.
    sub str-escape(\text) {
        my $codes := text.NFD;
        my int $i = -1;

        nqp::while(
          nqp::islt_i(++$i,nqp::elems($codes)),
          nqp::if(
            nqp::isle_i((my int $code = nqp::atpos_u($codes,$i)),92)
              || nqp::isge_i($code,128),
            nqp::if(                                       # not ascii
              nqp::isle_i($code,31),
              nqp::if(                                      # control
                nqp::iseq_i($code,10),
                nqp::splice($codes,$lf,$i++,1),              # \n
                nqp::if(
                  nqp::iseq_i($code,13),
                  nqp::splice($codes,$cr,$i++,1),             # \r
                  nqp::if(
                    nqp::iseq_i($code,9),
                    nqp::splice($codes,$tab,$i++,1),           # \t
                    nqp::stmts(                                # other control
                      nqp::splice($codes,$code.fmt(Q/\u%04x/).NFD,$i,1),
                      ($i = nqp::add_i($i,5))
                    )
                  )
                )
              ),
              nqp::if(                                      # not control
                nqp::iseq_i($code,34),
                nqp::splice($codes,$qq,$i++,1),              # "
                nqp::if(
                  nqp::iseq_i($code,92),
                  nqp::splice($codes,$bs,$i++,1),             # \
                  nqp::if(
                    nqp::isge_i($code,0x10000),
                    nqp::stmts(                                # surrogates
                      nqp::splice(
                        $codes,
                        (my $surrogate := to-surrogate-pair($code.chr).NFD),
                        $i,
                        1
                      ),
                      ($i = nqp::sub_i(nqp::add_i($i,nqp::elems($surrogate)),1))
                    )
                  )
                )
              )
            )
          )
        );

        nqp::strfromcodes($codes)
    }


    method to-json(
      \obj,
      Bool :$pretty        = False,
      Int  :$level         = 0,
      int  :$spacing       = 2,
      Bool :$sorted-keys   = False,
    ) {

        my $out := nqp::list_s;  # cannot use str @out because of JVM
        my str $spaces = ' ' x $spacing;
        my str $comma  = ",\n" ~ $spaces x $level;

#-- helper subs from here, with visibility to the above lexicals

        sub pretty-positional(\positional --> Nil) {
            $comma = nqp::concat($comma,$spaces);
            nqp::push_s($out,'[');
            nqp::push_s($out,nqp::substr($comma,1));

            for positional.list {
                jsonify($_);
                nqp::push_s($out,$comma);
            }
            nqp::pop_s($out);  # lose last comma

            $comma = nqp::substr($comma,0,nqp::sub_i(nqp::chars($comma),$spacing));
            nqp::push_s($out,nqp::substr($comma,1));
            nqp::push_s($out,']');
        }

        sub pretty-associative(\associative --> Nil) {
            $comma = nqp::concat($comma,$spaces);
            nqp::push_s($out,'{');
            nqp::push_s($out,nqp::substr($comma,1));
            my \pairs := $sorted-keys
              ?? associative.sort(*.key)
              !! associative.list;

            for pairs {
                jsonify(.key);
                nqp::push_s($out,": ");
                jsonify(.value);
                nqp::push_s($out,$comma);
            }
            nqp::pop_s($out);  # lose last comma

            $comma = nqp::substr($comma,0,nqp::sub_i(nqp::chars($comma),$spacing));
            nqp::push_s($out,nqp::substr($comma,1));
            nqp::push_s($out,'}');
        }

        sub unpretty-positional(\positional --> Nil) {
            nqp::push_s($out,'[');
            my int $before = nqp::elems($out);
            for positional.list {
                jsonify($_);
                nqp::push_s($out,",");
            }
            nqp::pop_s($out) if nqp::elems($out) > $before;  # lose last comma
            nqp::push_s($out,']');
        }

        sub unpretty-associative(\associative --> Nil) {
            nqp::push_s($out,'{');
            my \pairs := $sorted-keys
              ?? associative.sort(*.key)
              !! associative.list;

            my int $before = nqp::elems($out);
            for pairs {
                jsonify(.key);
                nqp::push_s($out,":");
                jsonify(.value);
                nqp::push_s($out,",");
            }
            nqp::pop_s($out) if nqp::elems($out) > $before;  # lose last comma
            nqp::push_s($out,'}');
        }

        sub jsonify(\obj --> Nil) {

            with obj {

                # basic ones
                when Bool {
                    nqp::push_s($out,obj ?? "true" !! "false");
                }
                when IntStr {
                    jsonify(.Int);
                }
                when RatStr {
                    jsonify(.Rat);
                }
                when NumStr {
                    jsonify(.Num);
                }
                when Str {
                    nqp::push_s($out,'"');
                    nqp::push_s($out,str-escape(obj));
                    nqp::push_s($out,'"');
                }

                # numeric ones
                when Int {
                    nqp::push_s($out,.Str);
                }
                when Rat {
                    nqp::push_s($out,.contains(".") ?? $_ !! "$_.0")
                      given .Str;
                }
                when FatRat {
                    nqp::push_s($out,.contains(".") ?? $_ !! "$_.0")
                      given .Str;
                }
                when Num {
                    if nqp::isnanorinf($_) {
                        nqp::push_s(
                          $out,
                          $*JSON_NAN_INF_SUPPORT ?? obj.Str !! "null"
                        );
                    }
                    else {
                        nqp::push_s($out,.contains("e") ?? $_ !! $_ ~ "e0")
                          given .Str;
                    }
                }

                # iterating ones
                when Seq {
                    jsonify(.cache);
                }
                when Positional {
                    $pretty
                      ?? pretty-positional($_)
                      !! unpretty-positional($_);
                }
                when Associative {
                    $pretty
                      ?? pretty-associative($_)
                      !! unpretty-associative($_);
                }

                # rarer ones
                when Dateish {
                    nqp::push_s($out,qq/"$_"/);
                }
                when Instant {
                    nqp::push_s($out,qq/"{.DateTime}"/)
                }
                when Version {
                    jsonify(.Str)
                }

                # also handle exceptions here
                when Exception {
                    jsonify(obj.^name => Hash.new(
                      (message => nqp::can(obj,"message")
                        ?? obj.message !! Nil
                      ),
                      obj.^attributes.grep(*.has_accessor).map: {
                          with .name.substr(2) -> $attr {
                              $attr => (
                                (.defined and not $_ ~~ Real|Positional|Associative)
                                  ?? .Str !! $_
                              ) given obj."$attr"()
                          }
                      }
                    ));
                }

                # huh, what?
                default {
                    jsonify( { 0 => 'null' } );
                }
            }
            else {
                nqp::push_s($out,'null');
            }
        }

#-- do the actual work

        jsonify(obj);
        nqp::join("",$out)
    }

    # there's a new version of from-json and friends that's a lot faster,
    # but it relies on the existence of the Uni type.
    # It doesn't exist on jvm, unfortunately.

    my $ws := nqp::list_i;
    nqp::bindpos_i($ws,  9, 1);  # \t
    nqp::bindpos_i($ws, 10, 1);  # \n
    nqp::bindpos_i($ws, 13, 1);  # \r
    nqp::bindpos_i($ws, 32, 1);  # space
    nqp::push_i($ws, 0);  # allow for -1 as value

    my sub nom-ws(str $text, int $pos is rw --> Nil) {
        nqp::while(
          nqp::atpos_i($ws, nqp::ordat($text, $pos)),
          $pos = nqp::add_i($pos, 1)
        )
    }


    my $hexdigits := nqp::list;
    nqp::bindpos($hexdigits,  48,  0);  # 0
    nqp::bindpos($hexdigits,  49,  1);  # 1
    nqp::bindpos($hexdigits,  50,  2);  # 2
    nqp::bindpos($hexdigits,  51,  3);  # 3
    nqp::bindpos($hexdigits,  52,  4);  # 4
    nqp::bindpos($hexdigits,  53,  5);  # 5
    nqp::bindpos($hexdigits,  54,  6);  # 6
    nqp::bindpos($hexdigits,  55,  7);  # 7
    nqp::bindpos($hexdigits,  56,  8);  # 8
    nqp::bindpos($hexdigits,  57,  9);  # 9
    nqp::bindpos($hexdigits,  65, 10);  # A
    nqp::bindpos($hexdigits,  66, 11);  # B
    nqp::bindpos($hexdigits,  67, 12);  # C
    nqp::bindpos($hexdigits,  68, 13);  # D
    nqp::bindpos($hexdigits,  69, 14);  # E
    nqp::bindpos($hexdigits,  70, 15);  # F
    nqp::bindpos($hexdigits,  97, 10);  # a
    nqp::bindpos($hexdigits,  98, 11);  # b
    nqp::bindpos($hexdigits,  99, 12);  # c
    nqp::bindpos($hexdigits, 100, 13);  # d
    nqp::bindpos($hexdigits, 101, 14);  # e
    nqp::bindpos($hexdigits, 102, 15);  # f

    my $escapees := nqp::list_i;
    nqp::bindpos_i($escapees,  34, 34);  # "
    nqp::bindpos_i($escapees,  47, 47);  # /
    nqp::bindpos_i($escapees,  92, 92);  # \
    nqp::bindpos_i($escapees,  98,  8);  # b
    nqp::bindpos_i($escapees, 102, 12);  # f
    nqp::bindpos_i($escapees, 110, 10);  # n
    nqp::bindpos_i($escapees, 114, 13);  # r
    nqp::bindpos_i($escapees, 116,  9);  # t


    my sub parse-string(str $text, int $pos is rw) {
        nqp::if(
          nqp::eqat($text, '"', nqp::sub_i($pos,1))  # starts with clean "
            && nqp::eqat($text, '"',                 # ends with clean "
                 (my int $end = nqp::findnotcclass(nqp::const::CCLASS_WORD,
                   $text, $pos, nqp::sub_i(nqp::chars($text),$pos)))
          ),
          nqp::stmts(
            (my $string := nqp::substr($text, $pos, nqp::sub_i($end, $pos))),
            ($pos = nqp::add_i($end,1)),
            $string
          ),
          parse-string-slow($text, $pos)
        )
    }

    # Slower parsing of string if the string does not exist of 0 or more
    # alphanumeric characters
    my sub parse-string-slow(str $text, int $pos is rw) {

        my int $start = nqp::sub_i($pos,1);  # include starter in string
        nqp::until(
          nqp::iseq_i((my $end := nqp::index($text, '"', $pos)), -1),
          nqp::stmts(
            ($pos = $end + 1),
            (my int $index = 1),
            nqp::while(
              nqp::eqat($text, '\\', nqp::sub_i($end, $index)),
              ($index = nqp::add_i($index, 1))
            ),
            nqp::if(
              nqp::bitand_i($index, 1),
              (return unjsonify-string(      # preceded by an even number of \
                nqp::strtocodes(
                  nqp::substr($text, $start, $end - $start),
                  nqp::const::NORMALIZE_NFD,
                  nqp::create(NFD)
                ),
                $pos
              ))
            )
          )
        );
        die "unexpected end of input in string";
    }

    # convert a sequence of Uni elements into a string, with the initial
    # quoter as the first element.
    my sub unjsonify-string(Uni:D \codes, int $pos) {
        nqp::shift_i(codes);  # lose the " without any decoration

        # fetch a single codepoint from the next 4 Uni elements
        my sub fetch-codepoint() {
            my int $codepoint = 0;
            my int $times = 5;

            nqp::while(
              ($times = nqp::sub_i($times, 1)),
              nqp::if(
                nqp::elems(codes),
                nqp::if(
                  nqp::iseq_i(
                    (my uint32 $ordinal = nqp::shift_i(codes)),
                    48  # 0
                  ),
                  ($codepoint = nqp::mul_i($codepoint, 16)),
                  nqp::if(
                    (my int $adder = nqp::atpos($hexdigits, $ordinal)),
                    ($codepoint = nqp::add_i(
                      nqp::mul_i($codepoint, 16),
                      $adder
                    )),
                    (die "invalid hexadecimal char {
                        nqp::chr($ordinal).perl
                    } in \\u sequence at $pos")
                  )
                ),
                (die "incomplete \\u sequence in string near $pos")
              )
            );

            $codepoint
        }

        my $output := nqp::create(Uni);
        nqp::while(
          nqp::elems(codes),
          nqp::if(
            nqp::iseq_i(
              (my uint32 $ordinal = nqp::shift_i(codes)),
              92  # \
            ),
            nqp::if(                                           # haz an escape
              nqp::iseq_i(($ordinal = nqp::shift_i(codes)), 117),  # u
              nqp::stmts(                                      # has a \u escape
                nqp::if(
                  nqp::isge_i((my int $codepoint = fetch-codepoint), 0xD800)
                    && nqp::islt_i($codepoint, 0xE000),
                  nqp::if(                                     # high surrogate
                    nqp::iseq_i(nqp::atpos_i(codes, 0),  92)        # \
                      && nqp::iseq_i(nqp::atpos_i(codes, 1), 117),  # u
                    nqp::stmts(                                # low surrogate
                      nqp::shift_i(codes),  # get rid of \
                      nqp::shift_i(codes),  # get rid of u
                      nqp::if(
                        nqp::isge_i((my int $low = fetch-codepoint), 0xDC00),
                        ($codepoint = nqp::add_i(              # got low surrogate
                          nqp::add_i(                          # transmogrify
                            nqp::mul_i(nqp::sub_i($codepoint, 0xD800), 0x400),
                            0x10000                            # with
                          ),                                   # low surrogate
                          nqp::sub_i($low, 0xDC00)
                        )),
                        (die "improper low surrogate \\u$low.base(16) for high surrogate \\u$codepoint.base(16) near $pos")
                      )
                    ),
                    (die "missing low surrogate for high surrogate \\u$codepoint.base(16) near $pos")
                  )
                ),
                nqp::push_i($output, $codepoint)
              ),
              nqp::if(                                         # other escapes?
                ($codepoint = nqp::atpos_i($escapees, $ordinal)),
                nqp::push_i($output, $codepoint),              # recognized escape
                (die "unknown escape code found '\\{           # huh?
                    nqp::chr($ordinal)
                }' found near $pos")
              )
            ),
            nqp::if(                                           # not an escape
              nqp::iseq_i($ordinal, 9) || nqp::iseq_i($ordinal, 10),  # \t \n
              (die "this kind of whitespace is not allowed in a string: '{
                  nqp::chr($ordinal).perl
              }' near $pos"),
              nqp::push_i($output, $ordinal)                   # ok codepoint
            )
          )
        );

        nqp::strfromcodes($output)
    }

    my sub parse-numeric(str $text, int $pos is rw) {
        my int $start = nqp::sub_i($pos,1);

        my int $end = nqp::findnotcclass(nqp::const::CCLASS_NUMERIC,
          $text, $pos, nqp::sub_i(nqp::chars($text),$pos));
        nqp::if(
          nqp::iseq_i(nqp::ordat($text, $end), 46),                      # .
          nqp::stmts(
            ($pos = nqp::add_i($end,1)),
            ($end = nqp::findnotcclass(nqp::const::CCLASS_NUMERIC,
              $text, $pos, nqp::sub_i(nqp::chars($text),$pos))
            )
          )
        );

        nqp::if(
          nqp::iseq_i((my int $ordinal = nqp::ordat($text, $end)), 101)  # e
           || nqp::iseq_i($ordinal, 69),                                 # E
          nqp::stmts(
            ($pos = nqp::add_i($end,1)),
            ($pos = nqp::add_i($pos,
              nqp::eqat($text, '-', $pos) || nqp::eqat($text, '+', $pos)
            )),
            ($end = nqp::findnotcclass(nqp::const::CCLASS_NUMERIC,
              $text, $pos, nqp::sub_i(nqp::chars($text),$pos))
            )
          )
        );

        my $result := nqp::substr($text, $start, nqp::sub_i($end,$start)).Numeric;
        nqp::if(
          nqp::istype($result, Failure),
          nqp::stmts(
            $result.Bool,  # handle Failure
            (die "at $pos: invalid number token $text.substr($start,$end - $start)")
          ),
          nqp::stmts(
            ($pos = $end),
            $result
          )
        )
    }

    my sub parse-obj(str $text, int $pos is rw) {
        my %result;
        my $hash := nqp::ifnull(
          nqp::getattr(%result,Map,'$!storage'),
          nqp::bindattr(%result,Map,'$!storage',nqp::hash)
        );

        nom-ws($text, $pos);
        my int $ordinal = nqp::ordat($text, $pos);
        nqp::if(
          nqp::iseq_i($ordinal, 125),  # }             {
          nqp::stmts(
            ($pos = nqp::add_i($pos,1)),
            %result
          ),
          nqp::stmts(
            my $descriptor := nqp::getattr(%result,Hash,'$!descriptor');
            nqp::stmts(  # this level is needed for some reason
              nqp::while(
                1,
                nqp::stmts(
                  nqp::if(
                    nqp::iseq_i($ordinal, 34),  # "
                    (my $key := parse-string($text, $pos = nqp::add_i($pos,1))),
                    (die nqp::if(
                      nqp::iseq_i($pos, nqp::chars($text)),
                      "at end of input: expected a quoted string for an object key",
                      "at $pos: json requires object keys to be strings"
                    ))
                  ),
                  nom-ws($text, $pos),
                  nqp::if(
                    nqp::iseq_i(nqp::ordat($text, $pos), 58),  # :
                    ($pos = nqp::add_i($pos, 1)),
                    (die "expected to see a ':' after an object key")
                  ),
                  nom-ws($text, $pos),
                  nqp::bindkey($hash, $key,
                    nqp::p6scalarwithvalue($descriptor, parse-thing($text, $pos))),
                  nom-ws($text, $pos),
                  ($ordinal = nqp::ordat($text, $pos)),
                  nqp::if(
                    nqp::iseq_i($ordinal, 125),  # }  {
                    nqp::stmts(
                      ($pos = nqp::add_i($pos,1)),
                      (return %result)
                    ),
                    nqp::unless(
                      nqp::iseq_i($ordinal, 44),  # ,
                      (die nqp::if(
                        nqp::iseq_i($pos, nqp::chars($text)),
                        "at end of input: unexpected end of object.",
                        "unexpected '{ nqp::substr($text, $pos, 1) }' in an object at $pos"
                      ))
                    )
                  ),
                  nom-ws($text, $pos = nqp::add_i($pos,1)),
                  ($ordinal = nqp::ordat($text, $pos)),
                )
              )
            )
          )
        )
    }


    my sub parse-array(str $text, int $pos is rw) {
        my @result;
        nqp::bindattr(@result, List, '$!reified',
          my $buffer := nqp::create(IterationBuffer));

        nom-ws($text, $pos);
        nqp::if(
          nqp::eqat($text, ']', $pos),
          nqp::stmts(
            ($pos = nqp::add_i($pos,1)),
            @result
          ),
          nqp::stmts(
            (my $descriptor := nqp::getattr(@result, Array, '$!descriptor')),
            nqp::while(
              1,
              nqp::stmts(
                (my $thing := parse-thing($text, $pos)),
                nom-ws($text, $pos),
                (my int $partitioner = nqp::ordat($text, $pos)),
                nqp::if(
                  nqp::iseq_i($partitioner,93),  # ]
                  nqp::stmts(
                    nqp::push($buffer,nqp::p6scalarwithvalue($descriptor,$thing)),
                    ($pos = nqp::add_i($pos,1)),
                    (return @result)
                  ),
                  nqp::if(
                    nqp::iseq_i($partitioner,44),  # ,
                    nqp::stmts(
                      nqp::push($buffer,nqp::p6scalarwithvalue($descriptor,$thing)),
                      ($pos = nqp::add_i($pos,1))
                    ),
                    (die "at $pos, unexpected partitioner '{
                        nqp::substr($text,$pos,1)
                    }' inside list of things in an array")
                  )
                )
              )
            )
          )
        )
    }

    my sub parse-thing(str $text, int $pos is rw) {
        nom-ws($text, $pos);

        my int $ordinal = nqp::ordat($text, $pos);
        if nqp::iseq_i($ordinal,34) {  # "
            parse-string($text, $pos = $pos + 1)
        }
        elsif nqp::iseq_i($ordinal,91) {  # [
            parse-array($text, $pos = $pos + 1)
        }
        elsif nqp::iseq_i($ordinal,123) {  # {
            parse-obj($text, $pos = $pos + 1)
        }
        elsif nqp::iscclass(nqp::const::CCLASS_NUMERIC, $text, $pos)
          || nqp::iseq_i($ordinal,45) {  # -
            parse-numeric($text, $pos = $pos + 1)
        }
        elsif nqp::iseq_i($ordinal,116) && nqp::eqat($text,'true',$pos) {
            $pos = $pos + 4;
            True
        }
        elsif nqp::iseq_i($ordinal,102) && nqp::eqat($text,'false',$pos) {
            $pos = $pos + 5;
            False
        }
        elsif nqp::iseq_i($ordinal,110) && nqp::eqat($text,'null',$pos) {
            $pos = $pos + 4;
            Any
        }
        else {
            die "at $pos: expected a json object, but got '{
              nqp::substr($text, $pos, 8).perl
            }'";
        }
    }

    method from-json(Str() $text) {
        CATCH { when X::AdHoc { die JSONException.new(:text($_)) } }

        my str $ntext   = $text;
        my int $length  = $text.chars;
        my int $pos     = 0;
        my     $result := parse-thing($text, $pos);

        try nom-ws($text, $pos);

        if $pos != nqp::chars($text) {
            die "additional text after the end of the document: { substr($text, $pos).raku }";
        }

        $result
    }


}

# vim: expandtab shiftwidth=4
