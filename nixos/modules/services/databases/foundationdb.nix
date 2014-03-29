{ config, pkgs, ... }:

with pkgs.lib;

let
  cfg = config.services.foundationdb;

  optionalNullStr = x: v: if x == null then "" else v;

  fdbServers = n:
    concatStringsSep "\n" (map (x: "[fdbserver.${toString (x+4500)}]") (range 0 (n - 1)));

  backupAgents = n:
    concatStringsSep "\n" (map (x: "[backup_agent.${toString (x+5500)}]") (range 0 (n - 1)));

  coordinators = concatStringsSep "," cfg.coordinators;

  cluster = ''${cfg.clusterDescription}:${cfg.clusterID}@${coordinators}'';

  conf = pkgs.writeText "foundationdb.conf"
    ''
    [fdbmonitor]
    user  = foundationdb
    group = foundationdb

    [general]
    restart_delay = ${toString cfg.restartDelay}
    cluster_file  = /etc/foundationdb/fdb.cluster

    [fdbserver]
    command        = ${pkgs.foundationdb}/sbin/fdbserver
    public_address = auto:$ID
    listen_address = public
    datadir        = /var/lib/foundationdb/data/$ID
    logdir         = /var/log/foundationdb
    logsize        = ${cfg.logSize}
    maxlogssize    = ${cfg.maxLogSize}
    memory         = ${cfg.memory}
    storage_memory = ${cfg.storageMemory}
    tls_plugin     = ${pkgs.foundationdb}/lib/foundationdb/plugins/FDBGnuTLS.so
    ${optionalNullStr cfg.tlsCert ("tls_certificate_file="+cfg.tlsCert)}
    ${optionalNullStr cfg.tlsKey  ("tls_key_file="+cfg.tlsKey)}
    ${optionalNullStr cfg.tlsVerifyPeers ("tls_verify_peers="+cfg.tlsVerifyPeers)}

    ${fdbServers cfg.serverProcesses}

    [backup_agent]
    command = ${pkgs.foundationdb}/lib/foundationdb/backup_agent/backup_agent

    ${backupAgents cfg.backupProcesses}
    '';
in
{
  options = {
    services.foundationdb = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "If enabled, start a FoundationDB server.";
      };

      pidfile = mkOption {
        type = types.path;
        default = "/tmp/foundationdb.pid";
        description = "Path to pidfile for fdbmonitor.";
      };

      restartDelay = mkOption {
        type = types.int;
        default = 60;
        description = "Number of seconds to wait before restarting servers.";
      };

      serverProcesses = mkOption {
        type = types.int;
        default = 1;
        description = "Number of fdbserver processes to run.";
      };

      backupProcesses = mkOption {
        type = types.int;
        default = 1;
        description = "Number of backup_agent processes to run for snapshots.";
      };

      clusterDescription = mkOption {
        type    = types.str;
        default = "local";
        description = "Cluster description";
      };

      clusterID = mkOption {
        type        = types.str;
        description = ''
          Cluster ID. An easy way to generate this is with
          <literal>mktemp -u XXXXXXXX</literal>.
        '';
      };

      coordinators = mkOption {
        type        = types.listOf types.str;
        default     = [ "127.0.0.1:4500" ];
        description = "List of coordination servers";
      };

      logSize = mkOption {
        type        = types.string;
        default     = "10MiB";
        description = ''
          Roll over to a new log file after the current log file
          reaches the specified size. The default value is
          <literal>10MiB</literal>.
        '';
      };

      maxLogSize = mkOption {
        type        = types.string;
        default     = "100MiB";
        description = ''
          Delete the oldest log file when the total size of all log
          files exceeds the specified size. If set to 0, old log files
          will not be deleted. The default value is
          <literal>100MiB</literal>.
        '';
      };

      memory = mkOption {
        type        = types.string;
        default     = "8GiB";
        description = ''
          Maximum memory used by the process. The default value is
          <literal>8GiB</literal>. When specified without a unit,
          <literal>MiB</literal> is assumed. This parameter does not
          change the memory allocation of the program. Rather, it sets
          a hard limit beyond which the process will kill itself and
          be restarted. The default value of <literal>8GiB</literal>
          is double the intended memory usage in the default
          configuration (providing an emergency buffer to deal with
          memory leaks or similar problems). It is not recommended to
          decrease the value of this parameter below its default
          value. It may be increased if you wish to allocate a very
          large amount of storage engine memory or cache. In
          particular, when the <literal>storageMemory</literal>
          parameter is increased, the <literal>memory</literal>
          parameter should be increased by an equal amount.
        '';
      };

      storageMemory = mkOption {
        type        = types.string;
        default     = "1GiB";
        description = ''
          Maximum memory used for data storage. The default value is
          <literal>1GiB</literal>. When specified without a unit,
          <literal>MB</literal> is assumed. Clusters using the memory
          storage engine will be restricted to using this amount of
          memory per process for purposes of data storage. Memory
          overhead associated with storing the data is counted against
          this total. If you increase the
          <literal>storageMemory</literal>, you should also increase
          the <literal>memory</literal> parameter by the same amount.
        '';
      };

      tlsCert = mkOption {
        type    = types.nullOr types.string;
        default = null;
        description = "Path to the TLS certificate file.";
      };

      tlsKey = mkOption {
        type    = types.nullOr types.string;
        default = null;
        description = "Path to the TLS certificate private key.";
      };

      tlsVerifyPeers = mkOption {
        type    = types.nullOr types.string;
        default = null;
        description = "Peer verification string.";
      };
    };
  };

  config = mkIf cfg.enable {

    users.extraGroups.foundationdb.gid = config.ids.gids.foundationdb;
    users.extraUsers.foundationdb = {
      description = "FoundationDB Service user";
      home        = "/var/lib/foundationdb";
      createHome  = true;
      group       = "foundationdb";
      uid         = config.ids.uids.foundationdb;
    };

    systemd.services.foundationdb = {
      description             = "FoundationDB Service";
      after                   = [ "network.target" ];
      wantedBy                = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "always";
        User    = "foundationdb";
        ExecStart =
          "${pkgs.foundationdb}/sbin/fdbmonitor --lockfile ${cfg.pidfile} --conffile /etc/foundationdb/foundationdb.conf";
        PermissionsStartOnly = true;
      };

      preStart = ''
        mkdir -p /var/log/foundationdb /var/lib/foundationdb/data
        chown -R foundationdb:foundationdb /var/log/foundationdb /var/lib/foundationdb
        mkdir -p /etc/foundationdb
        rm -f /etc/foundationdb/fdb.cluster && echo ${cluster} >> /etc/foundationdb/fdb.cluster
        cp ${conf} /etc/foundationdb/foundationdb.conf
        chown -Rf foundationdb:foundationdb /etc/foundationdb
        chmod -f 0644 /etc/foundationdb/fdb.cluster
      '';

      postStart = ''
        ${pkgs.foundationdb}/bin/fdbcli -C /etc/foundationdb/fdb.cluster --exec "configure new single memory" --timeout 60 2>&1 >/dev/null
      '';
    };

    environment.systemPackages = [ pkgs.foundationdb ];
  };
}
