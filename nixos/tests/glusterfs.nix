import ./make-test.nix ({ pkgs, ... }:

with pkgs.lib;

let
  server = { config, pkgs, ... }: {
    networking.firewall.enable = false;
    services.glusterfs.enable = true;
  };

  serverNum = 2;
  vars = concatStringsSep "," (map (x: "$gluster" + toString x) (range 1 serverNum));
in
{
  nodes = listToAttrs (map (r: {
    name  = "gluster" + toString r;
    value = server;
  }) (range 1 serverNum));

  testScript = ''
    startAll;

    foreach (${vars}) { $_->waitForUnit("glusterd.service"); }
  '';
})