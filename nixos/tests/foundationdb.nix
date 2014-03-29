import ./make-test.nix ({ pkgs, ... }:

with pkgs.lib;

let
  server = { config, pkgs, ... }: {
    networking.firewall.enable = false;

    services.foundationdb.enable       = true;
    services.foundationdb.clusterID    = "33ljC5fd";
    services.foundationdb.coordinators =
      [ "192.168.1.1:4500"
        "192.168.1.3:4500"
        "192.168.1.5:4500"
        "192.168.1.7:4500"
        "192.168.1.9:4500"
      ];
  };

  serverNum = 6;
  replicate = "triple";

  vars = concatStringsSep "," (map (x: "$fdb" + toString x) (range 1 serverNum));
in
{
  nodes = listToAttrs (map (r: {
    name  = "fdb" + toString r;
    value = server;
  }) (range 1 serverNum));

  testScript = ''
    startAll;

    foreach (${vars}) { $_->waitForUnit("foundationdb.service"); }
    $fdb1->succeed("fdbcli --exec 'configure ${replicate} memory'");

    foreach (${vars}) {
      $_->waitUntilSucceeds("fdbcli --exec 'status details' | grep -q 'Machines\\s*- ${toString serverNum}'");
      $_->waitUntilSucceeds("fdbcli --exec 'status details' | grep -q 'processes\\s*- ${toString serverNum}'");
    }

    $fdb1->waitUntilSucceeds("fdbcli --exec 'status details' | grep -q 'Healthy'");
  '';

})