{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hydownloader-systray;
in
{
  options.programs.hydownloader-systray = {
    enable = lib.mkEnableOption "Hydownloader systray";
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = config.services.hydrus.environmentFile;
      description = "Environment file containing the hydownloader access key as HYDOWNLOADER_ACCESS_KEY.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = config.services.hydrus.user;
      description = "User account which owns the hydownloader systray config.ini.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = config.services.hydrus.group;
      description = "Group which owns the hydownloader systray config.ini.";
    };
    settings = {
      instanceNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "default instance" ];
        description = "Instance names for hydownloader. Each instance is identified by its name in hydownloader-systray.";
      };
      apiURL = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "http://127.0.0.1:53211" ];
        description = "URL(s) of your hydownloader instance(s). Must match the number of instance names.";
      };
      defaultTests = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "environment" ];
        description = "Test names to prefill when starting tests from hydownloader-systray.";
      };
      defaultSubCheckInterval = lib.mkOption {
        type = lib.types.int;
        default = 48;
        description = "Default subscription check interval in hours (prefilled when adding subscriptions).";
      };
      applyDarkPalette = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable a basic dark theme. Might look incomplete on some systems.";
      };
      updateInterval = lib.mkOption {
        type = lib.types.int;
        default = 3000;
        description = "How often to query the hydownloader daemon for status and data updates (in milliseconds).";
      };
      startVisible = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether hydownloader-systray should start with the main window visible or minimized to systray.";
      };
      aggressiveUpdates = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "If true, will also refresh subscription, URL and subscription check lists on each update interval.";
      };
      localConnection = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set to true if hydownloader-systray is running on the same machine as hydownloader-daemon.";
      };
      disablePreviews = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to load/show image previews.";
      };
      userCss = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "User-defined stylesheet to apply to the UI (e.g. to override font size).";
      };
      forceStyle = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Force the use of the named Qt style (e.g. 'fusion' for uniform platform-independent look).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.hydrus.createUser = lib.mkDefault true;
    environment.systemPackages = [ pkgs.hydownloader-systray ];
    system.activationScripts.hydownloader-systray = lib.stringAfter [ "var" ] ''
      ${lib.optionalString (cfg.environmentFile != null) ''
        if [ -f "${cfg.environmentFile}" ]; then
          set -a  # Automatically export all variables
          source "${cfg.environmentFile}"
          set +a
        fi
      ''}
      mkdir -p /etc/hydownloader-systray
      chmod 0750 /etc/hydownloader-systray
      chown ${cfg.user}:${cfg.group} /etc/hydownloader-systray
      echo "instanceNames=${lib.concatStringsSep "," cfg.settings.instanceNames}
      accessKey=''${HYDOWNLOADER_ACCESS_KEY:-your access key here}
      apiURL=${lib.concatStringsSep "," cfg.settings.apiURL}
      defaultTests=${lib.concatStringsSep "," cfg.settings.defaultTests}
      defaultSubCheckInterval=${toString cfg.settings.defaultSubCheckInterval}
      applyDarkPalette=${lib.boolToString cfg.settings.applyDarkPalette}
      updateInterval=${toString cfg.settings.updateInterval}
      startVisible=${lib.boolToString cfg.settings.startVisible}
      aggressiveUpdates=${lib.boolToString cfg.settings.aggressiveUpdates}
      localConnection=${lib.boolToString cfg.settings.localConnection}
      disablePreviews=${lib.boolToString cfg.settings.disablePreviews}
      forceStyle=${cfg.settings.forceStyle}
      userCss=${cfg.settings.userCss}" | \
        ${pkgs.coreutils}/bin/install \
        -m 0640 -o ${cfg.user} -g ${cfg.group} \
        /dev/stdin /etc/hydownloader-systray/settings.ini
    '';
  };
}
