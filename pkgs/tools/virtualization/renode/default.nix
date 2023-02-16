{ stdenv
, lib
, fetchurl
, makeWrapper

, glibcLocales
, gtk2
, gtk2-x11
, pcre
, glib
, libffi
}:

let
  rpath = lib.makeLibraryPath [
    stdenv.cc.libc
    gtk2
    gtk2-x11
    pcre
    glib
    libffi
  ];
in

stdenv.mkDerivation rec {
  pname = "renode";
  version = "1.13.2";

  src = fetchurl {
    url = "https://github.com/${pname}/${pname}/releases/download/v${version}/renode-${version}.linux-portable.tar.gz";
    hash = "sha256-OvOlOELZ1eR3DURCoPe+WCvVyVm6DPKNcC1V7uauCjY=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # don't strip, so we don't accidentally break the rpaths, somehow
  dontStrip = true;

  buildPhase = ":";
  installPhase = ''
    mkdir -p $out/{bin,libexec/renode}

    mv * $out/libexec/renode
    mv .renode-root $out/libexec/renode
    chmod +x $out/libexec/renode/*.so

    cat > $out/bin/renode <<EOF
    #!${stdenv.shell}
    cd "$out/libexec/renode"
    export LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive
    export PATH="$out/libexec/renode:\$PATH"
    exec renode "\$@"
    EOF
    chmod +x $out/bin/renode
  '';

  # for some reason, autoPatchelfHook doesn't handle libc on these binaries? so we have to
  # apply the rpath to libc manually, anyway.
  postFixup = ''
    for x in renode libgdksharpglue-2.so libglibsharpglue-2.so libgtksharpglue-2.so libllvm-disas.so libmono-btls-shared.so; do
      p=$out/libexec/renode/$x
      patchelf --add-rpath ${rpath} $p
    done
  '';

  meta = {
    description = "Virtual development framework for complex embedded systems";
    homepage = "https://renode.org";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ thoughtpolice ];
    platforms = [ "x86_64-linux" ];
  };
}
