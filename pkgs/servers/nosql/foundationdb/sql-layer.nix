{ stdenv, fetchurl, makeWrapper, dpkg, jre }:

with stdenv.lib;

assert stdenv.system == "x86_64-linux";
stdenv.mkDerivation rec {
  name    = "foundationdb_sql-${version}-${rev}";
  version = "2.0.0";
  rev     = "1";

  src =
    [ ## Client package
      (fetchurl {
        url = "https://foundationdb.com/downloads/f-ifxooaxodfxcb/I_accept_the_FoundationDB_Community_License_Agreement/sql-layer/2.0.0/fdb-sql-layer-client-tools_2.0.0-1_all.deb";
        sha256 = "0ja54n69zmfbc1qlb5c4ds21d8bm0hbl5crknm84av6z3wg2xih0";
      })

      ## Server package
      (fetchurl {
        url = "https://foundationdb.com/downloads/f-ifxooaxodfxcb/I_accept_the_FoundationDB_Community_License_Agreement/sql-layer/2.0.0/fdb-sql-layer_2.0.0-1_all.deb";
        sha256 = "11p5zarls3k9gfb0l6jmf6zmjqshg7f5xma1sxm3ws2fy5yvallq";
      })

    ];

  unpackPhase = ''
    ${dpkg}/bin/dpkg-deb -x ${head src} .
    ${dpkg}/bin/dpkg-deb -x ${head (tail src)} .
  '';

  buildPhase  = false;
  installPhase = ''
    mkdir -p $out
    cd usr && cp -R * $out

    for x in bin/fdbsqlcli bin/fdbsqlprotod bin/fdbsqlload bin/fdbsqldump sbin/fdbsqllayer; do
      substituteInPlace $out/$x \
        --replace "java -cp" "${jre}/bin/java -cp" \
	--replace "\$JAVA_HOME/bin/java" "${jre}/bin/java" \
        --replace /usr/share/foundationdb/sql $out/share/foundationdb/sql
    done
  '';

  meta = {
    description = "A distributed, fault-tolerant SQL/OLTP database";
    homepage    = "https://foundationdb.com";
    license     = stdenv.lib.licenses.unfreeRedistributable;
    platforms   = [ "x86_64-linux" ];
    maintainers = [ stdenv.lib.maintainers.thoughtpolice ];
  };
}
