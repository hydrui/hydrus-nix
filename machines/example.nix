{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  testApiKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

  # Note: In real systems, use a secrets manager like sops-nix. The
  # environmentFile should be constructed at activation time, and be
  # readable only by root. Files in the nix store are world-readable!
  # For sops-nix, this can be constructed using templates.
  hydrusEnv = pkgs.writeText "hydrus-env" ''
    HYDRUS_DEFAULT_API_URL="http://127.0.0.1:45869"
    HYDRUS_DEFAULT_API_KEY="${testApiKey}"
    HYDOWNLOADER_ACCESS_KEY="${testApiKey}"
  '';
in
{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  # Could setting up hydrus and hydownloader inside of a netns really be this
  # easy? Only one way to find out.
  #
  # $ nixos-rebuild build-vm --flake .#example && ./result-bin/run-nixos-vm
  # $ nix run nixpkgs#xpra -- attach ssh://root@localhost:2222/0 --socket-dir=/run/hydrus-client
  services.hydrus = {
    client = {
      enable = true;
      environmentFile = hydrusEnv;
    };
    netns = {
      enable = true;
      extraStartScript = lib.getExe pkgs.hydrusTestutil.startWireguardTunnel;
      extraStopScript = lib.getExe pkgs.hydrusTestutil.stopWireguardTunnel;
    };
    hydownloader = {
      daemon = {
        enable = true;
        environmentFile = hydrusEnv;
        config.daemon.checkFreeSpace = false;
      };
    };
  };

  # Let's reverse-proxy the hydrus and hydownloader APIs out of the netns.
  # You can do whatever you want here. This example just uses basic nginx with
  # nothing special going on. You could also set up ACME if you wanted.
  # This isn't needed for any of the functionality, it just makes the API
  # accessible. You could also set up something fancy, like a Tailscale Funnel.
  services.nginx =
    let
      proxyPort = port: {
        serverName = "localhost";
        listen = [
          {
            inherit port;
            addr = "0.0.0.0";
          }
        ];
        locations."/" = {
          proxyPass = "http://${config.services.hydrus.netns.ipService}:${toString port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_connect_timeout 10m;
            proxy_read_timeout 10m;
            proxy_send_timeout 10m;
            client_max_body_size 1G;
            proxy_request_buffering off;
          '';
        };
      };
    in
    {
      enable = true;
      virtualHosts."hydrus-api" = proxyPort 45869;
      virtualHosts."hydownloader-api" = proxyPort 53211;
    };

  # Security? No thanks...
  users.mutableUsers = false;
  services.getty.autologinUser = "root";
  users.users.root.initialHashedPassword = "";
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };
  security.pam.services.sshd.allowNullPassword = true;
  virtualisation.forwardPorts = [
    {
      from = "host";
      host.port = 2222;
      guest.port = 22;
    }
    {
      from = "host";
      host.port = 45869;
      guest.port = 45869;
    }
    {
      from = "host";
      host.port = 53211;
      guest.port = 53211;
    }
  ];
  networking.firewall = {
    allowedTCPPorts = [
      45869
      53211
    ];
  };

  # Just some boilerplate, nothing to see here.
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;
  virtualisation.msize = 524288;
  boot.loader.grub.device = "/dev/sda";
  fileSystems."/".device = "/dev/sda1";
  system.stateVersion = "25.11";
}
