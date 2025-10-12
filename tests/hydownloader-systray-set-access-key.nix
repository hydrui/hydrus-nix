{
  self,
  nixpkgs,
  system,
  ...
}:
let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ self.outputs.overlays.default ];
  };
  accessKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
in
pkgs.nixosTest {
  name = "hydownloader-systray-default-settings";
  globalTimeout = 7200;
  nodes.client = {
    imports = [ self.outputs.nixosModules.default ];
    programs.hydownloader-systray = {
      environmentFile = pkgs.writeText "hydrus-env" ''
        HYDOWNLOADER_ACCESS_KEY="${accessKey}"
      '';
      enable = true;
    };
  };
  testScript = ''
    client.start()
    # If this fails it likely means the systray module needs to be updated!
    client.succeed("grep 'accessKey=${accessKey}' /etc/hydownloader-systray/settings.ini")
  '';
}
