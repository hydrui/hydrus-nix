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
  inherit (pkgs) lib;
  testApiKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  testImageHash = "9df84a3cff6f8a3f7d912c85d6d993f55085a4e29965b9f6f2a87336d972bd79";
  danbooruTestImageHash = "cad4cd142c4803234e9380591f58e5fed850fa50c06ebe22c94f61490d1844f5";
  danbooruHydlTestImageHash = "b4bdbff11a356a620ec6c7c08d4fb6affbb54b781e2c203cce05487689d2431b";
  hydrusEnv = pkgs.writeText "hydrus-env" ''
    HYDRUS_DEFAULT_API_URL="http://127.0.0.1:45869"
    HYDRUS_DEFAULT_API_KEY="${testApiKey}"
  '';
  wgDefault = "192.168.2.1";
  wgService = "192.168.2.2";
  ipDefault = "10.200.0.1";
  ipService = "10.200.0.2";
  # Turning the test derivation into a FOD allows "impure" Internet access.
  # This is so we can truly test features that rely on the Internet.
  fodArgs = {
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-pQpattmS9VmO3ZIQUFn66az8GSmB4IvYhTTCFn6SUmo=";
  };
in
(pkgs.testers.invalidateFetcherByDrvHash pkgs.testers.nixosTest {
  name = "hydrus-services-advanced";
  globalTimeout = 900;
  nodes = {
    client =
      { pkgs, ... }:
      {
        imports = [ self.outputs.nixosModules.default ];
        boot.kernel.sysctl."net.ipv4.ip_forward" = true;
        networking.firewall.allowedTCPPorts = [ 8080 ];
        services.nginx = {
          enable = true;
          virtualHosts."${wgDefault}" = {
            listen = [
              {
                addr = "0.0.0.0";
                port = 8080;
              }
            ];
            root = ./testdata;
          };
        };
        services.hydrus = {
          client = {
            enable = true;
            environmentFile = hydrusEnv;
          };
          netns = {
            enable = true;
            inherit ipDefault;
            inherit ipService;
            extraStartScript = lib.getExe (
              pkgs.hydrusTestutil.startWireguardTunnel.override { inherit wgDefault wgService; }
            );
            extraStopScript = lib.getExe (
              pkgs.hydrusTestutil.stopWireguardTunnel.override { inherit wgService; }
            );
          };
          hydownloader.daemon = {
            enable = true;
            environmentFile = hydrusEnv;
            config.daemon.checkFreeSpace = false;
          };
        };
        environment.systemPackages = [
          pkgs.curl
          pkgs.jq
        ];
      };
  };

  testScript = ''
    import json

    client.start()
    client.wait_for_unit("hydrus-client.service")
    client.wait_for_open_port(45869, "${ipService}")

    with subtest("Import image into Hydrus"):
      check_for_hash = (
        """
        curl --fail-with-body -G 'http://${ipService}:45869/get_files/file_metadata' \
          --data-urlencode 'hashes=["${testImageHash}"]' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          | grep -v '"file_id": null'
        """
      )
      client.fail(check_for_hash)
      response = client.succeed(
        """
        curl 'http://${ipService}:45869/add_urls/add_url' \
          -X POST \
          -H 'Content-Type: application/json' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          --data-raw '{"url":"http://${wgDefault}:8080/image.gif"}'
        """
      )
      print(response)
      api_response = json.loads(response)
      assert "success" in api_response["human_result_text"], f"Import didn't succeed: {api_response}"
      assert "hydrus_version" in api_response, f"Missing hydrus_version in response: {api_response}"
      assert "version" in api_response, f"Missing version in response: {api_response}"
      expected_version = ${toString pkgs.hydrus.version}
      assert api_response["hydrus_version"] == expected_version, \
        f"Version mismatch: got {api_response['hydrus_version']}, expected {expected_version}"
      client.wait_until_succeeds(check_for_hash)

    with subtest("Import image from Danbooru into Hydrus"):
      check_for_hash = (
        """
        curl --fail-with-body -G 'http://${ipService}:45869/get_files/file_metadata' \
          --data-urlencode 'hashes=["${danbooruTestImageHash}"]' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          | grep -v '"file_id": null'
        """
      )
      client.fail(check_for_hash)
      response = client.succeed(
        """
        curl 'http://${ipService}:45869/add_urls/add_url' \
          -X POST \
          -H 'Content-Type: application/json' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          --data-raw '{"url":"https://danbooru.donmai.us/posts/5078"}'
        """
      )
      api_response = json.loads(response)
      assert "success" in api_response["human_result_text"], f"Import didn't succeed: {api_response}"
      client.wait_until_succeeds(check_for_hash)

    with subtest("Import image from Danbooru using Hydownloader"):
      check_for_hash = (
        """
        curl --fail-with-body -G 'http://${ipService}:45869/get_files/file_metadata' \
          --data-urlencode 'hashes=["${danbooruHydlTestImageHash}"]' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          | grep -v '"file_id": null'
        """
      )
      client.fail(check_for_hash)
      client.succeed(
        """
        hydl mass-add-urls -p /var/lib/hydownloader/ \
          -f <(echo https://danbooru.donmai.us/posts/99470)
        """
      )
      client.wait_until_succeeds(check_for_hash)
  '';
}).overrideTestDerivation
  fodArgs
