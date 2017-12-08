{ stdenv, fetchurl, zlib, libpng
, docSupport ? false, doxygen ? null
}:
assert docSupport -> doxygen != null;

stdenv.mkDerivation rec {
  name = "pngpp-${version}";
  version = "0.2.9";

  src = fetchurl {
    url = "mirror://savannah/pngpp/png++-${version}.tar.gz";
    sha256 = "14c74fsc3q8iawf60m74xkkawkqbhd8k8x315m06qaqjcl2nmg5b";
  };

  propagatedBuildInputs = [ zlib libpng ];

  doCheck = false;
  enableParallelBuilding = true;

  makeFlags = [ "PREFIX=\${out}" ];
  NIX_LDFLAGS="-lpng -lz";

  meta = with stdenv.lib; {
    homepage = http://www.nongnu.org/pngpp/;
    description = "C++ wrapper for libpng library";
    license = licenses.bsd3;
    platforms = platforms.linux;
    maintainers = [ maintainers.ramkromberg ];
  };
}
