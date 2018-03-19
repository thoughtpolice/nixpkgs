{ stdenv, fetchFromGitHub, makeWrapper, cmake
, ncurses, readline, sqlite, lz4, zlib, openssl
, protobuf, protobufc, libuuid, libunwind
, flex, bison, tcl, tzdata
}:

with builtins;

stdenv.mkDerivation rec {
  name = "comdb2-${version}";
  version = "7.0.0pre-${substring 0 7 src.rev}";

  src = fetchFromGitHub {
    owner  = "bloomberg";
    repo   = "comdb2";
    rev    = "d5908b7f4637bd7fe9dd0da4ffcffc6ef7582c80";
    sha256 = "1f0q16zpm081h18aay9xmhv5gqqg9sc9v93hha0ywq8f4yp74pjx";
  };

  buildInputs =
    [ cmake ncurses readline sqlite lz4 zlib
      openssl protobuf protobufc libuuid libunwind
      flex bison tcl makeWrapper
    ];

  enableParallelBuilding = true;

  patchPhase = ''
    # Fix up some bash scripts used during the build
    patchShebangs .

    # Fix path to tzdata (hardcoded under /usr/share)
    substituteInPlace bb/comdb2file.c \
      --replace 'add_location("tzdata", "/usr/share/")' 'add_location("tzdata", "${tzdata}/share")'
  '';

  postInstall = ''
    # Remove empty directories for data/config files, since
    # they're unneeded in the output closure
    rm -rf $out/{etc,var,log}

    # Remove pmux/cdb2sockpool systemd units, and defunct
    # cdb directory
    rm -rf $out/lib/{systemd,cdb2}

    # Put multiple-output targets in the right place
    moveToOutput bin "$bin"
    moveToOutput lib "$lib"

    # Wrap programs to set sane COMDB2_DBHOME and COMDB2_ROOT
    # variables, used by the NixOS module
    for prog in "$bin"/bin/*; do
      wrapProgram "$prog" \
        --set COMDB2_DBHOME "/var/lib/cdb2/" \
        --set COMDB2_ROOT ""
    done
  '';

  postFixup = ''
    # Due to an annoying implementation detail of multiple-outputs.sh,
    # the $out target must always exist, but the comdb2 package always
    # has exactly the correct multiple outputs: there are never any
    # files left over to put inside $out, so the default fixupPhase
    # automatically removes $out when it sees it is empty. this makes
    # the generic builder mad, as it thinks the build has failed.
    #
    # work around this deficiency by just re-creating $out after
    # fixupPhase removes it, before the builder does a sanity check.
    mkdir $out

    # Fixup cdb2api.pc, which multiple-outputs.sh fails to do
    # correctly
    sed -i "/^prefix=/s/.*//"      $dev/lib/pkgconfig/cdb2api.pc
    sed -i "/^exec_prefix=/s/.*//" $dev/lib/pkgconfig/cdb2api.pc
    sed -i "/^libdir=/s,.*,libdir=$lib/lib," $dev/lib/pkgconfig/cdb2api.pc
    sed -i "/^includedir=/s,.*,includedir=$dev/include," $dev/lib/pkgconfig/cdb2api.pc
  '';

  outputs = [ "bin" "lib" "dev" "out" ];

  meta = {
    description = "Relational clustering database";
    homepage    = https://bloomberg.github.io/comdb2;
    license     = stdenv.lib.licenses.asl20;
    platforms   = stdenv.lib.platforms.linux;
    maintainers = with stdenv.lib.maintainers; [ thoughtpolice ];
  };
}
