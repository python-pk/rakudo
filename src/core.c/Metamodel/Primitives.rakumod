my class Metamodel::Primitives {
    method create_type(Mu $how, $repr = 'P6opaque', :$mixin = False) {
        my \type = $mixin
            ?? nqp::newmixintype($how, $repr.Str)
            !! nqp::newtype($how, $repr.Str);
        nqp::settypehll(type, 'Raku')
    }

    method set_package(Mu $type, $package) {
        nqp::setwho(nqp::decont($type), nqp::decont($package));
        $type
    }

    method install_method_cache(Mu $type, %cache, :$authoritative = True) {
        $type
    }

    method configure_type_checking(Mu $type, @cache, :$authoritative = True, :$call_accepts = False) {
        my Mu $cache := nqp::list();
        for @cache {
            nqp::push($cache, nqp::decont($_));
        }
        nqp::settypecache($type, $cache);
        nqp::settypecheckmode($type, $call_accepts
          ?? nqp::const::TYPE_CHECK_NEEDS_ACCEPTS
          !! $authoritative
            ?? nqp::const::TYPE_CHECK_CACHE_DEFINITIVE
            !! nqp::const::TYPE_CHECK_CACHE_THEN_METHOD
        );
        $type
    }

    method configure_destroy(Mu $type, $destroy) {
        nqp::settypefinalize($type, $destroy ?? 1 !! 0);
        $type
    }

    method compose_type(Mu $type, $configuration) {
        multi sub to_vm_types(@array) {
            my Mu $list := nqp::list();
            for @array {
                nqp::push($list, to_vm_types($_));
            }
            $list
        }
        multi sub to_vm_types(%hash) {
            my Mu $hash := nqp::hash();
            for %hash.kv -> $k, $v {
                nqp::bindkey($hash, $k, to_vm_types($v));
            }
            $hash
        }
        multi sub to_vm_types($other) {
            nqp::decont($other)
        }
        nqp::composetype(nqp::decont($type), to_vm_types($configuration));
        $type
    }

    method rebless(Mu $obj, Mu $type) {
        nqp::rebless($obj, $type)
    }

    method is_type(Mu \obj, Mu \type) {
        nqp::hllbool(nqp::istype(obj, type))
    }

    method set_parameterizer(Mu \obj, &parameterizer --> Nil) {
        my $wrapper := -> |c { parameterizer(|c) }
        nqp::setparameterizer(obj, nqp::getattr(nqp::decont($wrapper), Code, '$!do'))
    }

    method parameterize_type(Mu \obj, +parameters --> Mu) {
        my Mu $parameters := nqp::list();
        nqp::push($parameters, $_) for parameters;
        nqp::parameterizetype(obj, $parameters)
    }

    method type_parameterized(Mu \obj --> Mu) {
        nqp::typeparameterized(obj)
    }

    method type_parameters(Mu \obj --> List:D) {
        nqp::hllize(nqp::typeparameters(obj))
    }

    method type_parameter_at(Mu \obj, Int:D $idx --> Mu) is raw {
        nqp::typeparameterat(obj, nqp::decont_i($idx))
    }
}

# vim: expandtab shiftwidth=4
