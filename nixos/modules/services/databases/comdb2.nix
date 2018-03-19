{ config, lib, pkgs, ... }:

with lib;

let
  cfg  = config.services.comdb2;
in
{
  options.services.comdb2 = {
    enable = mkEnableOption "Comdb2 Relational Clustering Database";

    user = mkOption {
      type = types.str;
      default = "comdb2";
      description = "User account under which comdb2 runs.";
    };

    group = mkOption {
      type = types.str;
      default = "comdb2";
      description = "Group account under which comdb2 runs.";
    };

    allowGroupManagement = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Allow members of <literal>services.comdb2.group</literal> to
        control comdb2 systemd units for management purposes. This is
        done through the addition of a <literal>polkit(8)</literal>
        rule allowing <literal>systemctl</literal> commands for the
        <literal>comdb2XXX</literal> units.
      '';
    };

    databases = mkOption {
      description = "Declarative comdb2 databases";
      default = [ ];
      example = literalExample "[ ]";

      type = types.listOf (types.submodule { options = {
        name = mkOption {
          type = types.str;
          description = "Database name";
          example = "testdb";
        };

        schema = mkOption {
          type = types.str;
          description = "Declarative database schema (non-DDL based)";
          default = "";
          example = literalExample ''
            create table numbers {
              schema {
                int number
              }

              keys {
                "num" = number
              }
            }
          '';
        };
      };});
    };

    ## Port Mux service
    pmux = {
      listenPorts = mkOption {
        type = types.listOf types.int;
        default = [ 5105 ];
        description = "List of ports for pmux to listen on for comdb2 connections";
      };

      databasePorts = mkOption {
        type = types.listOf (types.submodule { options = {
          from = mkOption {
            type = types.int;
            description = "Start of port range, inclusive";
          };

          to = mkOption {
            type = types.int;
            description = "End of port range, inclusive";
          };
        };});

        default = [ { from = 19000; to = 19999; } ];

        example = literalExample "[ { from = 19000; to = 19999; } ]";
        description = "List of port ranges to allocate for comdb2 databases";
      };

      mode = mkOption {
        type = types.enum [ "FILE" "MEMORY" ];
        default = "MEMORY"; # TODO FIXME: use file mode?
        description = ''
          Operational mode. MEMORY means keep the port mapping data for comdb2
          in memory -- it will be lost when the pmux service shuts down. FILE
          means that the port database will be persisted on disk.
        '';
      };
    };

    # Socket pooling service for cdb2api
    sockpool = {
      enable = mkEnableOption "Comdb2 Connection Pooling service" // {
        default = true;
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = cfg.pmux.listenPorts != [] && cfg.pmux.databasePorts != [];
        message   = "You must configure listening ports and database port ranges!";
      }
    ];

    meta.doc = ./comdb2.xml;

    environment.systemPackages = [ pkgs.comdb2 ];

    system.activationScripts.comdb2setup = lib.stringAfter [ "users" "groups" ] ''
      mkdir -p {/var/log,/var/lib,/run}/cdb2
      chown -R ${cfg.user}:${cfg.group} {/var/log,/var/lib,/run}/cdb2
    '';

    security.polkit.extraConfig = mkIf cfg.allowGroupManagement ''
      // Allow '${cfg.group}' group users to manage comdb2 database services.
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.isInGroup("${cfg.group}") &&
            (action.lookup("unit") == "comdb2pmux.service" ||
             action.lookup("unit") == "comdb2sockpool.service" ||
             action.lookup("unit") == "comdb2init.service" ||
             (action.lookup("unit").startsWith("comdb2@") &&
              action.lookup("unit").endsWith(".service")))) {
          return polkit.Result.YES;
        }
      });
    '';

    users.extraUsers = optionalAttrs (cfg.user == "comdb2") (singleton
      { name = "comdb2";
        uid = config.ids.uids.comdb2;
        group = cfg.group;
        description = "Comdb2 Services User";
      });

    users.extraGroups = optionalAttrs (cfg.group == "comdb2") (singleton
      { name = "comdb2";
        gid = config.ids.gids.comdb2;
      });

    environment.etc = builtins.listToAttrs (map (db:
      nameValuePair "cdb2/schemas/${db.name}.cdbsql" {
        text = db.schema;
      }) cfg.databases);

    # Sigh. This is a configuration purely determined by the client, not
    # server, but it gives a very annoying default of 'America/New_York' if it
    # isn't set. Globally set it to the users local timezone, so all their
    # queries will come back with a sensible default. It can be overridden
    # per-connection.
    environment.variables.COMDB2TZ = "${config.time.timeZone}";

    systemd.services."comdb2@" =
      let
        needed = map (p: "${p}.service") [ "comdb2pmux" "comdb2sockpool" ];
      in {
        description = "Comdb2 Database '%i'";
        path        = [ pkgs.comdb2 config.systemd.package ];

        after       = [ "multi-user.target" ] ++ needed;
        requires    = needed;

        serviceConfig.Type       = "notify";
        serviceConfig.Restart    = "always";
        serviceConfig.RestartSec = "1";
        serviceConfig.User       = cfg.user;
        serviceConfig.Group      = cfg.group;

        serviceConfig.NotifyAccess = "all";
        serviceConfig.PermissionsStartOnly = true;
        serviceConfig.TimeoutSec = 300;

        unitConfig.RequiresMountsFor = "/var/lib/cdb2/%i /var/log/cdb2";

        serviceConfig.ExecStart = "${pkgs.writeTextFile {
          name = "start-comdb2";
          executable = true;
          text = ''
            #!${pkgs.stdenv.shell} -e

            systemd-notify --ready --status="Starting comdb2 server"
            exec ${pkgs.comdb2}/bin/comdb2 --lrl "/var/lib/cdb2/''$1/''$1.lrl" "''$1";
          '';
        }} \"%i\"";

        serviceConfig.ExecStartPre = "${pkgs.writeTextFile {
          name = "create-cdb2-dbs";
          executable = true;
          text = ''
            #!${pkgs.stdenv.shell} -e

            if [ ! -d "/var/lib/cdb2/''$1" ]; then
              systemd-notify --status="Creating database"
              ${pkgs.sudo}/bin/sudo -u ${cfg.user} comdb2 --create "''$1"
              systemd-notify --status="Database created"
            fi
          '';
        }} \"%i\"";

        serviceConfig.ExecStartPost = "${pkgs.writeTextFile {
          name = "update-cdb2-schemas";
          executable = true;
          text = ''
            #!${pkgs.stdenv.shell} -e

            systemd-notify --status="Waiting for full startup"
            while ! ${pkgs.sudo}/bin/sudo -u ${cfg.user} cdb2sql -s "''$1" 'select 1+1 as "math"'; do
              if ! kill -0 "$MAINPID"; then exit 1; fi
              sleep 0.1
            done

            systemd-notify --status="Adjusting schema at startup"
            cat "/etc/cdb2/schemas/''$1.cdbsql" | ${pkgs.sudo}/bin/sudo -u ${cfg.user} cdb2sql -s "''$1"
            #systemd-ask-password --id="comdb2:''$1" "Initial database password for 'comdb2' user:"
            systemd-notify --status="Ready to serve queries"
          '';
        }} \"%i\"";
      };

    systemd.services.comdb2pmux = {
      description = "Comdb2 Port Mux Service";
      after       = [ "multi-user.target" ];

      serviceConfig.Type    = "forking";
      serviceConfig.Restart = "always";

      serviceConfig.User  = cfg.user;
      serviceConfig.Group = cfg.group;

      script = ''
        exec ${pkgs.comdb2}/bin/pmux \
          ${if cfg.pmux.mode == "MEMORY" then "-n" else "-l"} \
          ${lib.concatStringsSep " " (map (x: "-p ${toString x}") cfg.pmux.listenPorts)} \
          ${lib.concatStringsSep " " (map (r: "-r ${toString r.from}:${toString r.to}") cfg.pmux.databasePorts)} \
          -b /run/cdb2/pmux.socket
      '';
    };

    systemd.services.comdb2sockpool = mkIf cfg.sockpool.enable {
      description = "Comdb2 Connection Pooling Service";
      after       = [ "multi-user.target" ];

      serviceConfig.Type    = "forking";
      serviceConfig.Restart = "always";

      serviceConfig.User  = cfg.user;
      serviceConfig.Group = cfg.group;

      environment.MSGTRAP_SOCKPOOL = "/run/cdb2/sockpool.fifo";
      script = ''
        exec ${pkgs.comdb2}/bin/cdb2sockpool \
          -p /run/cdb2/sockpool.socket
      '';
    };
  };
}
