{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.glusterfs;
in
{
  options = {
    services.glusterfs = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the <literal>glusterd</literal> daemon.";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.glusterd = {
      description = "GlusterFS Daemon";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];
      before      = [ "network-online.target" ];

      preStart = "mkdir -p /var/lib/gluster";

      serviceConfig.Type = "forking";
      serviceConfig.ExecStart =
        "${pkgs.glusterfs}/sbin/glusterd -p /run/glusterd.pid -l /var/lib/gluster/glusterd.vol.log";
      serviceConfig.PIDFile   = "/run/glusterd.pid";
      serviceConfig.Restart   = "always";
    };
  };
}
