{ stdenv, fetch, clang, clang-unwrapped, perl, makeWrapper, version }:

stdenv.mkDerivation rec {
  name = "clang-analyzer-${version}";
  src  = fetch "cfe" "1myssbxlyln0nggfz04nfrbzdckljksmaxp82nq7hrmqjc62vybl";

  patches = [ ./analyzer-cflags.patch ];
  buildInputs = [ clang clang-unwrapped perl makeWrapper ];
  buildPhase = "true";

  installPhase = ''
    mkdir -p $out/bin $out/libexec
    cp -R tools/scan-view  $out/libexec
    cp -R tools/scan-build $out/libexec

    makeWrapper $out/libexec/scan-view/scan-view $out/bin/scan-view
    makeWrapper $out/libexec/scan-build/scan-build $out/bin/scan-build \
      --add-flags "--use-cc=${clang}/bin/clang" \
      --add-flags "--use-c++=${clang}/bin/clang++" \
      --add-flags "--use-analyzer='${clang-unwrapped}/bin/clang'"
  '';

  meta = {
    description = "Clang Static Analyzer";
    homepage    = "http://clang-analyzer.llvm.org";
    license     = stdenv.lib.licenses.bsd3;
    platforms   = stdenv.lib.platforms.unix;
    maintainers = [ stdenv.lib.maintainers.thoughtpolice ];
  };
}
