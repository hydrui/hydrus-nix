final: prev: {
  hydownloader = final.callPackage ./packages/hydownloader/package.nix { };
  hydownloader-systray = final.callPackage ./packages/hydownloader-systray/package.nix { };
  hydrus = final.callPackage ./packages/hydrus/package.nix { };
  hydrusTestutil = {
    startWireguardTunnel =
      final.callPackage ./packages/hydrusTestutil/startWireguardTunnel/package.nix
        { };
    stopWireguardTunnel =
      final.callPackage ./packages/hydrusTestutil/stopWireguardTunnel/package.nix
        { };
  };
}
