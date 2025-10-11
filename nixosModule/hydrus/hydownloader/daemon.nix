{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hydrus.hydownloader.daemon;
  importJobHeaderText = builtins.concatStringsSep "\n" [
    cfg.importJob.preCommonConfig
    cfg.importJob.commonConfig
    cfg.importJob.postCommonConfig
    cfg.importJob.defaultImportJob
    cfg.importJob.defaultRules
  ];
  importJobRulesText = builtins.concatStringsSep "\n" (builtins.attrValues cfg.importJob.rules);
  importJobText = builtins.concatStringsSep "\n" [
    "# DO NOT EDIT! This file is rewritten EVERY TIME the service restarts"
    "# Use the config.services.hydrus.hydownloader.daemon.importJob options instead."
    "# If you wish to manually construct a file, you must disable this by"
    "# setting config.services.hydrus.hydownloader.daemon.importJob.enable to false."
    importJobHeaderText
    importJobRulesText
  ];
in
{
  options.services.hydrus.hydownloader.daemon = {
    enable = lib.mkEnableOption "Hydownloader daemon service";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hydownloader;
      defaultText = lib.literalExpression "pkgs.hydownloader";
      description = "The hydownloader package to use";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hydownloader";
      description = "Directory where hydownloader stores its database and data";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the default hydownloader ports";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = config.services.hydrus.user;
      description = "User account under which hydownloader runs";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = config.services.hydrus.group;
      description = "Group under which hydownloader runs";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments to pass to hydownloader-daemon";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = config.services.hydrus.environmentFile;
      description = "Environment file containing the hydownloader access key as HYDOWNLOADER_ACCESS_KEY.";
    };
    importJob = {
      enable = lib.mkEnableOption "Managed Hydownloader import job config" // {
        default = true;
      };
      preCommonConfig = lib.mkOption {
        type = lib.types.str;
        default = ''
          import os
        '';
        description = "Configuration to insert before the commonConfig section";
      };
      commonConfig = lib.mkOption {
        type = lib.types.str;
        default = pkgs.hydownloader.passthru.importJob.commonConfig;
        description = "Common configuration for the import job; typically includes hydrus client credentials and tag services";
      };
      postCommonConfig = lib.mkOption {
        type = lib.types.str;
        default = ''
          defAPIURL = os.getenv('HYDRUS_DEFAULT_API_URL')
          defAPIKey = os.getenv('HYDRUS_DEFAULT_API_KEY')
        '';
        description = "Configuration to insert after the commonConfig section";
      };
      defaultImportJob = lib.mkOption {
        type = lib.types.str;
        default = pkgs.hydownloader.passthru.importJob.defaultImportJob;
        description = "Sets up the default import job used by all of the rules by default";
      };
      defaultRules = lib.mkOption {
        type = lib.types.str;
        default = pkgs.hydownloader.passthru.importJob.defaultRules;
        description = "Sets up the default rule set used for all files without more specific rule sets";
      };
      rules = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = pkgs.hydownloader.passthru.importJob.rules;
        description = "Rules configuration for specific sites";
      };
    };
    config = {
      enable = lib.mkEnableOption "Managed Hydownloader config overrides" // {
        default = true;
      };
      daemon = {
        port = lib.mkOption {
          type = lib.types.int;
          default = 53211;
          description = "Override for the daemon.port option";
        };
        host = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Override for the daemon.host option";
        };
        ssl = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Override for the daemon.ssl option";
        };
        checkFreeSpace = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Override for the daemon.check-free-space option";
        };
      };
    };
  };
  config = lib.mkIf cfg.enable {
    services.hydrus.createUser = lib.mkDefault true;
    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.config.daemonPort ];
    };
    environment.systemPackages = [
      pkgs.hydownloader
    ];
    systemd.services.hydownloader = {
      description = "Hydownloader Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        ExecStartPre = lib.getExe (
          pkgs.writeShellApplication {
            name = "hydownloader-config-setup";
            runtimeInputs = [
              cfg.package
              pkgs.jq
              pkgs.moreutils
            ];
            text = ''
              if [ ! -f "${cfg.dataDir}/hydownloader.db" ] && [ ! -f "${cfg.dataDir}/.initialized" ]; then
                echo "Initializing hydownloader database."
                hydl init-db -p "${cfg.dataDir}"
                touch "${cfg.dataDir}/.initialized"
                echo "Done."
              fi
              ${lib.optionalString cfg.config.enable ''
                echo "Setting config overrides"
                jq -f <(
                  echo '."daemon.port" = ${toString cfg.config.daemon.port}' &&
                  echo '| ."daemon.host" = "${toString cfg.config.daemon.host}"' &&
                  echo '| ."daemon.ssl" = ${lib.boolToString cfg.config.daemon.ssl}' &&
                  echo '| ."daemon.check-free-space" = ${lib.boolToString cfg.config.daemon.checkFreeSpace}' &&
                  [ -n "''${HYDOWNLOADER_ACCESS_KEY:-}" ] && echo "| .\"daemon.access-key\" = \"$HYDOWNLOADER_ACCESS_KEY\""
                ) "${cfg.dataDir}/hydownloader-config.json" | sponge "${cfg.dataDir}/hydownloader-config.json"
              ''}
              ${lib.optionalString cfg.importJob.enable ''
                echo "Setting import jobs override"
                cp \
                  ${builtins.toFile "hydownloader-import-jobs.py" importJobText} \
                  "${cfg.dataDir}/hydownloader-import-jobs.py"
              ''}
            '';
          }
        );
        ExecStart = "${cfg.package}/bin/hydownloader-daemon start --path ${cfg.dataDir} ${lib.escapeShellArgs cfg.extraArgs}";
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
        StateDirectory = "hydownloader";
        StateDirectoryMode = "0750";
      };
    };
  };
}
