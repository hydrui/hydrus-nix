{
  self,
  nixpkgs,
  system,
  ...
}:
let
  pkgs = import nixpkgs {
    inherit system;
  };
in
pkgs.testers.nixosTest {
  name = "hydownloader-systray-default-settings";
  globalTimeout = 900;
  nodes.client = {
    imports = [ self.outputs.nixosModules.default ];
    programs.hydownloader-systray.enable = true;
  };
  testScript = ''
    client.start()
    # If this fails it likely means the systray module needs to be updated!
    client.succeed("diff /etc/hydownloader-systray/settings.ini ${self.outputs.packages.${system}.hydownloader-systray.src}/settings.ini")
  '';
}
