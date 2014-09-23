{ stdenv, fetchurl, which, zlib, pkgconfig, SDL, openssl, libaio
, libuuid, gettext, ncurses, dev86, iasl, pciutils, bzip2, xz, yajl
, lvm2, utillinux, procps, texinfo, perl, pythonPackages, glib, wget
, fetchgit }:

with stdenv.lib;

let
  libDir = if stdenv.is64bit then "lib64" else "lib";

  seabiosSrc =
    [ { url    = "git://xenbits.xen.org/seabios.git";
        rev    = "refs/tags/rel-1.7.3.1";
        sha256 = "a50a5ab6d992f5598edd92105059fae9acfc192981e08bd88534c2167e92526a";
      } ];
in
stdenv.mkDerivation rec {
  name = "xen-${version}";
  version = "4.4.1";

  src = fetchurl {
    url = "http://bits.xensource.com/oss-xen/release/${version}/xen-${version}.tar.gz";
    sha256 = "09gaqydqmy64s5pqnwgjyzhd3wc61xyghpqjfl97kmvm8ly9vd2m";
  };

  buildInputs =
    [ which zlib pkgconfig SDL openssl libuuid gettext ncurses yajl
      dev86 iasl pciutils bzip2 xz texinfo perl glib wget libaio
      pythonPackages.python pythonPackages.wrapPython
    ];

  pythonPath = [ pythonPackages.curses ];

  configureFlags = "--disable-stubdom";

  makeFlags = "PREFIX=$(out) CONFIG_DIR=/etc";

  buildFlags = "xen tools";

  preBuild =
    ''
      substituteInPlace tools/libfsimage/common/fsimage_plugin.c \
        --replace /usr $out

      substituteInPlace tools/blktap2/lvm/lvm-util.c \
        --replace /usr/sbin/vgs ${lvm2}/sbin/vgs \
        --replace /usr/sbin/lvs ${lvm2}/sbin/lvs

      substituteInPlace tools/hotplug/Linux/network-bridge \
        --replace /usr/bin/logger ${utillinux}/bin/logger

      substituteInPlace tools/xenmon/xenmon.py \
        --replace /usr/bin/pkill ${procps}/bin/pkill

      substituteInPlace tools/xenstat/Makefile \
        --replace /usr/include/curses.h ${ncurses}/include/curses.h

      substituteInPlace tools/qemu-xen-traditional/xen-hooks.mak \
        --replace /usr/include/pci ${pciutils}/include/pci

      # Work around a bug in our GCC wrapper: `gcc -MF foo -v' doesn't
      # print the GCC version number properly.
      substituteInPlace xen/Makefile \
        --replace '$(CC) $(CFLAGS) --version' '$(CC) --version'

      substituteInPlace tools/python/xen/xend/server/BlktapController.py \
        --replace /usr/sbin/tapdisk2 $out/sbin/tapdisk2

      substituteInPlace tools/python/xen/xend/XendQCoWStorageRepo.py \
        --replace /usr/sbin/qcow-create $out/sbin/qcow-create

      substituteInPlace tools/python/xen/remus/save.py \
        --replace /usr/lib/xen/bin/xc_save $out/${libDir}/xen/bin/xc_save

      substituteInPlace tools/python/xen/remus/device.py \
        --replace /usr/lib/xen/bin/imqebt $out/${libDir}/xen/bin/imqebt

      # Allow the location of the xendomains config file to be
      # overriden at runtime.
      substituteInPlace tools/hotplug/Linux/init.d/xendomains \
        --replace 'XENDOM_CONFIG=/etc/sysconfig/xendomains' "" \
        --replace /bin/ls ls
    '';

  postBuild = "make -C docs man-pages";
  installPhase =
    ''
      mkdir -p $out
      cp -prvd dist/install/nix/store/*/* $out/
      cp -prvd dist/install/boot $out/boot
      cp -prvd dist/install/etc $out/etc
      cp -dR docs/man1 docs/man5 $out/share/man/
      wrapPythonPrograms
    ''; # */

  meta = {
    homepage = http://www.xen.org/;
    description = "Xen hypervisor and management tools for Dom0";
    platforms = [ "i686-linux" "x86_64-linux" ];
    maintainers = with stdenv.lib.maintainers; [ eelco thoughtpolice ];
  };
}
