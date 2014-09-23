# Xen hypervisor (Dom0) support.

{ config, lib, pkgs, ... }:

with lib;

let
  xen = pkgs.xen;
  cfg = config.virtualisation.xen;

  fullBootParams = [ "loglvl=all" "guest_loglvl=all" ] ++
    optional (cfg.dom0MemSize != 0) "dom0_mem=${toString cfg.dom0MemSize}M";

  xendConfig = pkgs.writeText "xend-config.sxp"
    ''
      (loglevel DEBUG)
      (network-script network-bridge)
      (vif-script vif-bridge)
    '';
in
{
  options = {
    virtualisation.xen = {
      enable = mkOption {
        default = false;
        description = "Enable Xen hypervisor Dom0 support.";
      };

      bootParams = mkOption {
        default = "";
        description = "Parameters passed to the Xen hypervisor at boot time.";
      };

      dom0MemSize = mkOption {
        default = 0;
        example = 512;
        description = ''
          Amount of memory (in MiB) allocated to Domain 0 on boot.
          If set to 0, all memory is assigned to Domain 0.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # Domain 0 requires a pvops-enabled kernel.
    # TODO FIXME: unset this for prod later
    boot.kernelPackages = pkgs.linuxPackages_3_16;

    # Enable Xen kernel modules, and blacklist the radeonfb kernel
    # module causes the screen to go black as soon as it's loaded.
    # TODO FIXME: does this still occur?
    boot.blacklistedKernelModules = [ "radeonfb" ];
    boot.kernelModules =
      [ "xen_evtchn" "xen_gntdev" "xen_blkback" "xen_netback" "xen_pciback"
        "blktap" "tun"
      ];

    # Increase the number of loopback devices from the default (8),
    # which is way too small because every VM virtual disk requires a
    # loopback device.
    boot.extraModprobeConfig = "options loop max_loop=128";

    # Enable boot params.
    system.extraSystemBuilderCmds = ''
      ln -s ${xen}/boot/xen.gz $out/xen.gz
      echo "${toString cfg.bootParams}" > $out/xen-params
    '';

    # Mount the /proc/xen pseudo-filesystem.
    system.activationScripts.xen = ''
      if [ -d /proc/xen ]; then
          ${pkgs.sysvtools}/bin/mountpoint -q /proc/xen || \
              ${pkgs.utillinux}/bin/mount -t xenfs none /proc/xen
      fi
    '';

    jobs.xend =
      { description = "Xen Control Daemon";

        startOn = "stopped udevtrigger";

        path =
          [ pkgs.bridge_utils pkgs.gawk pkgs.iproute pkgs.nettools
            pkgs.utillinux pkgs.bash xen pkgs.pciutils pkgs.procps
          ];

        environment.XENCONSOLED_TRACE = "hv";

        preStart =
          ''
            mkdir -p /var/log/xen/console -m 0700

            ${xen}/sbin/xend start

            # Wait until Xend is running.
            for ((i = 0; i < 60; i++)); do echo "waiting for xend..."; ${xen}/sbin/xend status && break; done

            ${xen}/sbin/xend status || exit 1
          '';

        postStop = "${xen}/sbin/xend stop";
      };

    jobs.xendomains =
      { description = "Automatically starts, saves and restores Xen domains on startup/shutdown";

        startOn = "started xend";

        stopOn = "starting shutdown and stopping xend";

        restartIfChanged = false;
        
        path = [ pkgs.xen ];

        environment.XENDOM_CONFIG = "${xen}/etc/sysconfig/xendomains";

        preStart =
          ''
            mkdir -p /var/lock/subsys -m 755
            ${xen}/etc/init.d/xendomains start
          '';

        postStop = "${xen}/etc/init.d/xendomains stop";
      };

    # To prevent a race between dhcpcd and xend's bridge setup script
    # (which renames eth* to peth* and recreates eth* as a virtual
    # device), start dhcpcd after xend.
    jobs.dhcpcd.startOn = mkOverride 50 "started xend";

    # Enable packages, udev rules, and etc setup.
    environment.systemPackages = [ xen ];
    services.udev.packages = [ xen ];
    services.udev.path = [ pkgs.bridge_utils pkgs.iproute ];

    environment.etc."xen/xend-config.sxp".source = xendConfig
    environment.etc."xen/scripts".source = "${xen}/etc/xen/scripts";
  };
}
