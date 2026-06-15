final: prev: {
  hydrus-api = final.python3Packages.callPackage ./packages/hydrus-api/package.nix { };
  pillow-jpegxl-plugin =
    final.python3Packages.callPackage ./packages/pillow-jpegxl-plugin/package.nix
      {
      };
  hydownloader = final.callPackage ./packages/hydownloader/package.nix { };
  hydownloader-systray = final.callPackage ./packages/hydownloader-systray/package.nix { };
  hydrus = final.callPackage ./packages/hydrus/package.nix {
    pillow-jpegxl-plugin = final.pillow-jpegxl-plugin;
  };
  hydrusTestutil = {
    startWireguardTunnel =
      final.callPackage ./packages/hydrusTestutil/startWireguardTunnel/package.nix
        { };
    stopWireguardTunnel =
      final.callPackage ./packages/hydrusTestutil/stopWireguardTunnel/package.nix
        { };
  };
  python3Packages = prev.python3Packages // {
    curl-adapter = final.python3Packages.callPackage ./packages/curl-adapter/package.nix { };
  };
  gallery-dl = prev.gallery-dl.overrideAttrs (old: {
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
      final.python3Packages.curl-adapter
    ];
    patches = (old.patches or [ ]) ++ [
      ./packages/gallery-dl/curl-impersonate.patch
    ];
  });
}
