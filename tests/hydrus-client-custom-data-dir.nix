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
  testApiKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  testImageHash = "9df84a3cff6f8a3f7d912c85d6d993f55085a4e29965b9f6f2a87336d972bd79";
  hydrusEnv = pkgs.writeText "hydrus-env" ''
    HYDRUS_DEFAULT_API_KEY="${testApiKey}"
  '';
in
pkgs.testers.nixosTest {
  name = "hydrus-client-custom-data-dir";
  globalTimeout = 900;
  nodes = {
    client =
      { pkgs, ... }:
      {
        imports = [ self.outputs.nixosModules.default ];
        services.hydrus.client = {
          enable = true;
          environmentFile = hydrusEnv;
          dataDir = "/data/hydrus";
        };
        networking.firewall.allowedTCPPorts = [ 8080 ];
        services.nginx = {
          enable = true;
          virtualHosts."localhost" = {
            listen = [
              {
                addr = "0.0.0.0";
                port = 8080;
              }
            ];
            root = ./testdata;
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
    client.wait_for_open_port(45869)

    with subtest("Import image into Hydrus"):
      check_for_hash = (
        """
        curl --fail-with-body -G 'http://localhost:45869/get_files/file_metadata' \
          --data-urlencode 'hashes=["${testImageHash}"]' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          | grep -v '"file_id": null'
        """
      )
      client.fail(check_for_hash)
      response = client.succeed(
        """
        curl 'http://localhost:45869/add_urls/add_url' \
          -X POST \
          -H 'Content-Type: application/json' \
          -H 'Hydrus-Client-API-Access-Key: ${testApiKey}' \
          --data-raw '{"url":"http://localhost:8080/image.gif"}'
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
      client.succeed("ls /data/hydrus/client.db")
  '';
}
