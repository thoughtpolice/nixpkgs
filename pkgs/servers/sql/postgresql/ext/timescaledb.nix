{ stdenv, fetchFromGitHub, cmake, postgresql }:

# # To enable on NixOS:
# config.services.postgresql = {
#   extraPlugins = [ pkgs.timescaledb ];
#   extraConfig = "shared_preload_libraries = 'timescaledb'";
# }

stdenv.mkDerivation rec {
  name = "timescaledb-${version}";
  version = "0.11.0";

  nativeBuildInputs = [ cmake ];
  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner  = "timescale";
    repo   = "timescaledb";
    rev    = "refs/tags/${version}";
    sha256 = "06xysf45r0c2sjfl6vgdbrm7pn7nxx2n0k29bm88q0ipyyp9fr0v";
  };

  # Fix the install phase which tries to install into the pgsql extension dir,
  # and cannot be manually overridden. This is rather fragile but works OK.
  patchPhase = ''
    for x in CMakeLists.txt sql/CMakeLists.txt; do
      substituteInPlace "$x" \
        --replace 'DESTINATION "''${PG_SHAREDIR}/extension"' "DESTINATION \"$out/share/extension\""
    done

    for x in src/CMakeLists.txt src/loader/CMakeLists.txt; do
      substituteInPlace "$x" \
        --replace 'DESTINATION ''${PG_PKGLIBDIR}' "DESTINATION \"$out/lib\""
    done
  '';

  passthru = {
    versionCheck = builtins.compareVersions postgresql.version "9.6" >= 0;
  };

  meta = with stdenv.lib; {
    description = "Scales PostgreSQL for time-series data via automatic partitioning across time and space";
    homepage    = https://www.timescale.com/;
    maintainers = with maintainers; [ volth ];
    platforms   = platforms.linux;
    license     = licenses.postgresql;
  };
}
