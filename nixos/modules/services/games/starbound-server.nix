{ config, pkgs, ... }:

with pkgs.lib;

let
  cfg          = config.services.starbound-server;
  conf = pkgs.writeText "starbound-bootstrap.config" ''
    { "assetSources" : [
        "${pkgs.starbound-server}/share/starbound/assets/packed.pak",
        "${pkgs.starbound-server}/share/starbound/assets/music",
        "${pkgs.starbound-server}/share/starbound/assets/user"
      ],
      "modSource":        "/var/lib/starbound/mods",
      "storageDirectory": "/var/lib/starbound/data"
    }
  '';
in
{
  options = {
    services.starbound-server = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = '';
          If enabled, start the Starbound Server.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    users.extraGroups.starbound.gid = config.ids.gids.starbound;
    users.extraUsers.starbound = {
      description = "Starbound Server user";
      home        = "/var/lib/starbound/";
      createHome  = true;
      group       = "starbound";
      uid         = config.ids.uids.starbound;
    };

    systemd.services.starbound-server = {
      description = "Starbound Server Service";
      after       = [ "network.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig = {
        Restart   = "always";
        User      = "starbound";
        ExecStart = "${pkgs.starbound-server}/bin/starbound-server -bootconfig ${conf}";
      };
    };
  };
}
