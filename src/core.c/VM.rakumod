class VM does Systemic {

    has $.config         is built(:bind) = nqp::backendconfig;
    has $.prefix         is built(:bind) = $!config<prefix>;
    has $.precomp-ext    is built(:bind) = "moarvm";
    has $.precomp-target is built(:bind) = "mbc";


    submethod TWEAK(--> Nil) {

        
        nqp::bind($!name,'moar');
        nqp::bind($!desc,'Short for "Metamodel On A Runtime", MoarVM is a modern virtual machine built for the Rakudo compiler and the NQP Compiler Toolchain.');
        nqp::bind($!auth,'The MoarVM Team');
        nqp::bind($!version,Version.new($!config<version> // "unknown"));

# add new backends here please
    }


    method platform-library-name(IO::Path $library, Version :$version) {
        my int $is-win = Rakudo::Internals.IS-WIN;
        my int $is-darwin = self.osname eq 'darwin';

        my $basename  = $library.basename;
        my int $full-path = $library ne $basename;
        my $dirname   = $library.dirname;

        # OS X needs version before extension
        $basename ~= ".$version" if $is-darwin && $version.defined;


        my $dll = self.config<dll>;
        my $platform-name = sprintf($dll, $basename);


        $platform-name ~= '.' ~ $version
            if $version.defined and nqp::iseq_i(nqp::add_i($is-darwin,$is-win),0);

        $full-path
          ?? $dirname.IO.add($platform-name).absolute
          !! $platform-name.IO
    }

    method own-up() {

        nqp::syscall("all-thread-bt",1);

    }

    proto method osname(|) {*}
    multi method osname(VM:U:) {

        nqp::lc(nqp::atkey(nqp::backendconfig,'osname'))

    }
    multi method osname(VM:D:) {

        nqp::lc($!config<osname>)

    }

    method remote-debugging() {

        nqp::syscall("is-debugserver-running")

    }

    method request-garbage-collection(--> Nil) {

        nqp::force_gc

    }
}

Rakudo::Internals.REGISTER-DYNAMIC: '$*VM', {
    PROCESS::<$VM> := VM.new;
}

# vim: expandtab shiftwidth=4
