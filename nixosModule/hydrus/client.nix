{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hydrus.client;
in
{
  options.services.hydrus.client = {
    enable = lib.mkEnableOption "Hydrus network client daemon";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hydrus;
      defaultText = lib.literalExpression "pkgs.hydrus";
      description = "The hydrus package to use";
    };
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/run/hydrus-client";
      description = "Directory where the hydrus network service stores sockets and runtime data";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hydrus-client";
      description = "Directory where the hydrus network client stores its database and data";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the default hydownloader ports";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = config.services.hydrus.user;
      description = "User account under which the hydrus network client runs";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = config.services.hydrus.group;
      description = "Group under which the hydrus network client runs";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--pause_network_traffic" ];
      description = "Extra arguments to pass to hydrus-client";
    };
    extraXpraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--bind=${cfg.stateDir}/,html"
        "--socket-permissions=0750"
      ];
      description = "Extra arguments to pass to xpra server";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = config.services.hydrus.environmentFile;
      description = "Environment file containing API key to create, if desired, as HYDRUS_DEFAULT_API_KEY";
    };
    initialDatabase = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a directory containing compressed initial Hydrus database files
        (client.db.zst, client.caches.db.zst, client.mappings.db.zst,
        client.master.db.zst). If set, these files will be copied to the data
        directory on first start (when client.db does not yet exist).
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    services.hydrus.createUser = lib.mkDefault true;
    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 45869 ];
    };
    environment.systemPackages = [
      pkgs.xpra
    ];
    systemd.services.hydrus-client = {
      description = "Hydrus network client daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        ExecStartPre = lib.mkIf (cfg.initialDatabase != null) (
          lib.getExe (
            pkgs.writeShellApplication {
              name = "hydrus-client-db-init";
              text = ''
                if [ ! -f "${cfg.dataDir}/client.db" ]; then
                  echo "Seeding hydrus client database from initial database."
                  cp ${cfg.initialDatabase}/client*.db.zst "${cfg.dataDir}/"
                  ${lib.getExe pkgs.zstd} --rm -d "${cfg.dataDir}"/client*.db.zst
                  chmod 0640 "${cfg.dataDir}"/client*.db
                  # Create the client_files directory structure that Hydrus expects
                  for prefix in f t; do
                    for i in $(seq 0 255); do
                      printf -v hex '%02x' "$i"
                      mkdir -p "${cfg.dataDir}/client_files/''${prefix}''${hex}"
                    done
                  done
                  echo "Done."
                fi
              '';
            }
          )
        );
        ExecStart =
          let
            startHydrusCommand = pkgs.writeShellScript "start-hydrus-command" ''
              exec ${cfg.package}/bin/hydrus-client -d ${cfg.dataDir} ${lib.escapeShellArgs cfg.extraArgs}
            '';
            startHydrusXpraCommand = pkgs.writeShellScript "start-hydrus-xpra-command" ''
              export PATH="${
                lib.makeBinPath [
                  pkgs.pulseaudio.out
                  pkgs.dbus.out
                ]
              }:\$PATH"
              XDG_RUNTIME_DIR=${lib.escapeShellArg cfg.stateDir} \
              exec ${pkgs.xpra}/bin/xpra start \
                --daemon=no \
                --exit-with-children=yes \
                --start-child=${startHydrusCommand} \
                ${lib.escapeShellArgs cfg.extraXpraArgs}
            '';
          in
          "${startHydrusXpraCommand}";
        Restart = "on-failure";
        RestartSec = 10;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Needed for FFI :I
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallFilter = "@system-service";
        SystemCallErrorNumber = "EPERM";
        PrivateNetwork = false;
        RuntimeDirectory = "hydrus-client";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "hydrus-client";
        StateDirectoryMode = "0750";
      };
    };
  };
}
