{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.hydrus;
in
{
  imports = [
    ./hydownloader
    ./client.nix
    ./netns.nix
  ];
  options.services.hydrus = {
    createUser = mkEnableOption "Hydrus user account";
    user = mkOption {
      type = types.str;
      default = "hydrus";
      description = "User account under which hydrus network programs run";
    };
    group = mkOption {
      type = types.str;
      default = "hydrus";
      description = "Group under which hydrus network programs run";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Environment file to use for hydrus-related programs.
        May contain the following variables:
        - HYDRUS_DEFAULT_API_URL: URL of Hydrus API to use
        - HYDRUS_DEFAULT_API_KEY: Hydrus API key to create/use
        - HYDOWNLOADER_ACCESS_KEY: Hydownloader API key to set/use
      '';
    };
  };
  config = lib.mkIf cfg.createUser {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Hydrus network user";
    };
    users.groups.${cfg.group} = { };
  };
}
