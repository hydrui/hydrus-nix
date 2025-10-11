{
  description = "Hydrus Network Nix flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };
  outputs =
    inputs@{
      nixpkgs,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      overlay = import ./overlay;
      nixosModule = {
        imports = [ ./nixosModule ];
        config.nixpkgs.overlays = [ overlay ];
      };
      systems = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
          args = inputs // {
            inherit system;
          };
        in
        {
          packages = {
            default = pkgs.hydrus;
            hydownloader = pkgs.hydownloader;
            hydownloader-systray = pkgs.hydownloader-systray;
            hydrus = pkgs.hydrus;
          };
          apps = {
            hydrus-client = {
              type = "app";
              program = "${pkgs.hydrus}/bin/hydrus-client";
              meta.description = "Hydrus network client";
            };
            hydrus-server = {
              type = "app";
              program = "${pkgs.hydrus}/bin/hydrus-server";
              meta.description = "Hydrus network server";
            };
            hydl = {
              type = "app";
              program = "${pkgs.hydownloader}/bin/hydl";
              meta.description = "Hydownloader CLI";
            };
            hydownloader-daemon = {
              type = "app";
              program = "${pkgs.hydownloader}/bin/hydownloader-daemon";
              meta.description = "Hydownloader daemon";
            };
            hydownloader-importer = {
              type = "app";
              program = "${pkgs.hydownloader}/bin/hydownloader-importer";
              meta.description = "Hydownloader importer";
            };
            hydownloader-tools = {
              type = "app";
              program = "${pkgs.hydownloader}/bin/hydownloader-tools";
              meta.description = "Hydownloader tools";
            };
          };
          checks = nixpkgs.lib.genAttrs [
            "hydownloader-systray-default-settings"
            "hydownloader-systray-set-access-key"
            "hydrus-client-custom-data-dir"
            "hydrus-services-advanced"
            "hydrus-services-basic"
          ] (test: import (./tests + "/${test}.nix") args);
        }
      );
    in
    {
      packages = forAllSystems (system: systems.${system}.packages);
      apps = forAllSystems (system: systems.${system}.apps);
      checks = forAllSystems (system: systems.${system}.checks);
      overlays.default = overlay;
      nixosModules.default = nixosModule;
      nixosModules.hydownloader = nixosModule;
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixosModule
          ./machines/example.nix
        ];
      };
    };
}
