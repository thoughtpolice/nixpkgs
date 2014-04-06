{ stdenv, requireFile }:

let
  arch = if stdenv.system == "x86_64-linux" then "x64"
    else if stdenv.system == "i686-linux" then "x32"
    else throw "starbound_server: ${stdenv.system} not supported!";
  exe = "starbound_server." + arch;

  libPath = stdenv.lib.makeLibraryPath
    [ stdenv.gcc.libc
      stdenv.gcc.gcc
    ] + ":${stdenv.gcc.gcc}/lib64";
in
stdenv.mkDerivation rec {
  name    = "starbound-server-${version}";
  version = "20140219";

  src = requireFile {
    message = ''
      You must package the Starbound Server privately. Please create a
      tarball with the package data and server exes, then run:

      nix-prefetch-url file:///path/to/${name}.tar.xz
    '';
    name   = "${name}.tar.xz";
    sha256 = "96f2a930f7d10fd414545d2d9ce9c64b75439d4389d980ccd91ab6f5cf5ed677";
  };

  buildPhase = false;

  installPhase = ''
    mkdir -p $out/bin $out/share
    mv ${exe} $out/bin/starbound-server
    mv * $out/share
  '';

  fixupPhase = ''
    patchelf --interpreter "$(cat $NIX_GCC/nix-support/dynamic-linker)" \
      --set-rpath ${libPath} $out/bin/starbound-server
  '';

  meta = {
    description = "Starbound Server package";
    homepage    = "http://playstarbound.com";
    license     = stdenv.lib.licenses.unfree;
    platforms   = stdenv.lib.platforms.linux;
    maintainers = [ stdenv.lib.maintainers.thoughtpolice ];
  };
}
