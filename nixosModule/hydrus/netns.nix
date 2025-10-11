{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hydrus.netns;
  netnsPath = "/run/netns/${cfg.name}";
in
{
  options.services.hydrus.netns = {
    enable = lib.mkEnableOption "Hydrus network netns setup";
    name = lib.mkOption {
      type = lib.types.str;
      description = "Name of network namespace to create";
      default = "hydrus";
    };
    resolvconfBind = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "If specified, path to bind-mount to /etc/resolv.conf";
      example = "/etc/netns/mynetns/resolv.conf";
      default = null;
    };
    vethDefault = lib.mkOption {
      type = lib.types.str;
      description = "Name of veth to create in default namespace";
      default = "veth-hydrusdef";
    };
    vethService = lib.mkOption {
      type = lib.types.str;
      description = "Name of veth to create in hydrus namespace";
      default = "veth-hydrussvc";
    };
    ipDefault = lib.mkOption {
      type = lib.types.str;
      description = "IP address for veth pair in default namespace";
      default = "10.200.0.1";
    };
    ipService = lib.mkOption {
      type = lib.types.str;
      description = "IP address for veth pair in hydrus namespace";
      default = "10.200.0.2";
    };
    subnetMask = lib.mkOption {
      type = lib.types.str;
      description = "Subnet mask to use for veth subnet";
      default = "30";
    };
    extraStartScript = lib.mkOption {
      type = lib.types.str;
      description = "Extra script to run during start";
      default = "";
    };
    extraStopScript = lib.mkOption {
      type = lib.types.str;
      description = "Extra script to run during stop";
      default = "";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.hydrus-netns = {
      description = "Hydrus network netns";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "hydrus-netns-start";
            runtimeInputs = [
              pkgs.iproute2
            ];
            text = ''
              echo "Creating network namespace" ${lib.escapeShellArg cfg.name}
              ip netns add ${lib.escapeShellArg cfg.name}
              echo "Creating veth pair"
              ip link add ${lib.escapeShellArg cfg.vethDefault} type veth peer name ${lib.escapeShellArg cfg.vethService}
              echo "Moving service end of veth pair into network namespace" ${lib.escapeShellArg cfg.name}
              ip link set ${lib.escapeShellArg cfg.vethService} netns ${lib.escapeShellArg cfg.name}
              echo "Setting up address of default end of veth pair"
              ip addr add ${lib.escapeShellArg "${cfg.ipDefault}/${cfg.subnetMask}"} dev ${lib.escapeShellArg cfg.vethDefault}
              echo "Setting default end of veth pair up"
              ip link set ${lib.escapeShellArg cfg.vethDefault} up
              echo "Setting up loopback interface in network namespace"
              ip netns exec ${lib.escapeShellArg cfg.name} ip link set lo up;
              echo "Setting up address of service end of veth pair"
              ip netns exec ${lib.escapeShellArg cfg.name} ip addr add ${lib.escapeShellArg "${cfg.ipService}/${cfg.subnetMask}"} dev ${lib.escapeShellArg cfg.vethService}
              echo "Setting service end of veth pair up"
              ip netns exec ${lib.escapeShellArg cfg.name} ip link set ${lib.escapeShellArg cfg.vethService} up
              ${cfg.extraStartScript}
            '';
          }
        );
        ExecStop = lib.getExe (
          pkgs.writeShellApplication {
            name = "hydrus-netns-stop";
            runtimeInputs = [
              pkgs.iproute2
            ];
            text = ''
              ${cfg.extraStopScript}
              echo "Deleting veth pair"
              ip link delete ${lib.escapeShellArg cfg.vethDefault} || echo "Couldn't delete veth pair"
              echo "Deleting network namespace" ${lib.escapeShellArg cfg.name}
              ip netns del ${lib.escapeShellArg cfg.name} || echo "Couldn't delete network namespace"
            '';
          }
        );
      };
    };
    systemd.services.hydrus-client = {
      bindsTo = [ "hydrus-netns.service" ];
      after = [ "hydrus-netns.service" ];
      serviceConfig = {
        NetworkNamespacePath = netnsPath;
        BindReadOnlyPaths = lib.mkIf (cfg.resolvconfBind != null) "${cfg.resolvconfBind}:/etc/resolv.conf";
      };
    };
    systemd.services.hydownloader = {
      bindsTo = [ "hydrus-netns.service" ];
      after = [ "hydrus-netns.service" ];
      serviceConfig = {
        NetworkNamespacePath = netnsPath;
        BindReadOnlyPaths = lib.mkIf (cfg.resolvconfBind != null) "${cfg.resolvconfBind}:/etc/resolv.conf";
      };
    };
  };
}
