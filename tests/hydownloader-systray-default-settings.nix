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
in
pkgs.nixosTest {
  name = "hydownloader-systray-default-settings";
  nodes.client = {
    imports = [ self.outputs.nixosModules.default ];
    programs.hydownloader-systray.enable = true;
  };
  testScript = ''
    client.start()
    # If this fails it likely means the systray module needs to be updated!
    client.succeed("diff /etc/hydownloader-systray/settings.ini ${pkgs.hydownloader-systray.src}/settings.ini")
  '';
}
