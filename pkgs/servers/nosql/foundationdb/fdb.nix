{ stdenv, fetchurl, makeWrapper, patchelf, dpkg, python27 }:

with stdenv.lib;

let
  python = python27; # May get upgraded in the future

  libPath = stdenv.lib.makeLibraryPath [ stdenv.gcc.libc ];

  patchLib = x: "patchelf --set-rpath ${libPath} ${x}";
  patchBin = x: ''
    patchelf --interpreter "$(cat $NIX_GCC/nix-support/dynamic-linker)" \
      --set-rpath ${libPath} ${x}
  '';

  fixPythonPath = x: ''
    substituteInPlace ${x} --replace /usr/bin/python ${python}/bin/python
    wrapProgram "${x}" --prefix PYTHONPATH : $out/lib/${python.libPrefix}/site-packages
  '';
in

assert stdenv.system == "x86_64-linux";
stdenv.mkDerivation rec {
  name    = "foundationdb-${version}-${rev}";
  version = "2.0.9";
  rev     = "1";

  src =
    [ ## Client package
      (fetchurl {
        url = "https://foundationdb.com/downloads/I_accept_the_FoundationDB_Community_License_Agreement/${version}/foundationdb-clients_${version}-${rev}_amd64.deb";
        sha256 = "1kabzkcahxdwrgmc0zyld7ywwvwqlshdkghnpsbrg6c3q9yfk247";
      })

      ## Server package
      (fetchurl {
        url = "https://foundationdb.com/downloads/I_accept_the_FoundationDB_Community_License_Agreement/${version}/foundationdb-server_${version}-${rev}_amd64.deb";
        sha256 = "162ihb0992m54gvs3pv7xhmk8waginaamyymcln8f5rcls2ipdph";
      })
    ];

  buildInputs = [ patchelf makeWrapper ];
  dontStrip = true; # Otherwise, strip incorrectly removes needed segments

  unpackPhase = ''
    ${dpkg}/bin/dpkg-deb -x ${head src} .
    ${dpkg}/bin/dpkg-deb -x ${head (tail src)} .
  '';

  buildPhase  = false;
  installPhase = ''
    mkdir -p $out

    cd usr && cp -R * $out && cd ..
    mv $out/lib/${python.libPrefix}/dist-packages $out/lib/${python.libPrefix}/site-packages

    ${fixPythonPath "$out/lib/foundationdb/backup_agent/backup_agent"}
    ${fixPythonPath "$out/lib/foundationdb/backup_agent/fdbrestore"}
    ${fixPythonPath "$out/lib/foundationdb/backup_agent/fdbbackup"}
    ${patchBin "$out/bin/fdbcli"}
    ${patchBin "$out/sbin/fdbmonitor"}
    ${patchBin "$out/sbin/fdbserver"}
    ${patchLib "$out/lib/python2.7/site-packages/fdb/libfdb_c.so"}
    ${patchLib "$out/lib/libfdb_c.so"}
    ${patchLib "$out/lib/foundationdb/plugins/FDBGnuTLS.so"}
  '';

  meta = {
    description = "A distributed, fault-tolerant ACID database";
    homepage    = "https://foundationdb.com";
    license     = stdenv.lib.licenses.unfreeRedistributable;
    platforms   = [ "x86_64-linux" ];
    maintainers = [ stdenv.lib.maintainers.thoughtpolice ];
  };
}
