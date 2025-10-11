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
        ExecStartPre = pkgs.writeShellScript "hydrus-client-db-init" ''
          if [ -n "$HYDRUS_DEFAULT_API_KEY" ] && [ ! -f "${cfg.dataDir}/client.db" ] && [ ! -f "${cfg.dataDir}/.initialized" ]; then
            # There's no dedicated way to just run migrations, so let's just
            # run the hydrus client for a moment with offscreen rendering.
            # The timeout 10s is arbitrary, but if it's too short the hydrus
            # client quits before creating all of its data directories, which
            # causes warnings on "real" first boot.
            echo "Initializing hydrus client database."
            QT_QPA_PLATFORM=offscreen \
            ${pkgs.coreutils.out}/bin/timeout -s SIGINT 10s \
              ${cfg.package}/bin/hydrus-client -d ${cfg.dataDir}

            # Set up the API. This is a pretty bad hack, but it's probably
            # still less fragile than automating the UI or something.
            SERVICE_CONFIG_HEX=$(echo -n '[21, 2, [[[0, "port"], [0, 45869]], [[0, "upnp_port"], [0, null]], [[0, "allow_non_local_connections"], [0, true]], [[0, "support_cors"], [0, true]], [[0, "log_requests"], [0, false]], [[0, "use_normie_eris"], [0, true]], [[0, "bandwidth_tracker"], [2, [39, 1, [[], [], [], [], [], [], [], [], [], []]]]], [[0, "bandwidth_rules"], [2, [38, 1, []]]], [[0, "external_scheme_override"], [0, null]], [[0, "external_host_override"], [0, null]], [[0, "external_port_override"], [0, null]], [[0, "use_https"], [0, false]]]]'  | ${pkgs.unixtools.xxd.out}/bin/xxd -p -c0)
            ${pkgs.sqlite.bin}/bin/sqlite3 ${cfg.dataDir}/client.db "UPDATE services SET dictionary_string = X'$SERVICE_CONFIG_HEX' WHERE service_type = 18;"
            API_KEY_CONFIG_HEX=$(echo -n "[[76, \"new api permissions\", 2, [\"$HYDRUS_DEFAULT_API_KEY\", true, [], [44, 1, []]]]]" | ${pkgs.unixtools.xxd.out}/bin/xxd -p -c0)
            ${pkgs.sqlite.bin}/bin/sqlite3 ${cfg.dataDir}/client.db "UPDATE json_dumps SET dump = X'$API_KEY_CONFIG_HEX' WHERE dump_type = 75;"

            touch "${cfg.dataDir}/.initialized"
            echo "Done."
          fi
        '';
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
