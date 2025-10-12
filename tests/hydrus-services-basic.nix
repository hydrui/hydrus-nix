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
  hydrusEnv = pkgs.writeText "hydrus-env" ''
    HYDRUS_DEFAULT_API_KEY="${testApiKey}"
  '';
in
pkgs.nixosTest {
  name = "hydrus-services-basic";
  globalTimeout = 900;
  nodes = {
    client =
      { pkgs, ... }:
      {
        imports = [ self.outputs.nixosModules.default ];
        services.hydrus.client = {
          enable = true;
          environmentFile = hydrusEnv;
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

    with subtest("API version endpoint returns correct JSON"):
      response = client.succeed(
        "curl -s http://localhost:45869/api_version"
      )
      api_response = json.loads(response)

      assert "hydrus_version" in api_response, f"Missing hydrus_version in response: {api_response}"
      assert "version" in api_response, f"Missing version in response: {api_response}"

      expected_version = ${toString pkgs.hydrus.version}
      assert api_response["hydrus_version"] == expected_version, \
        f"Version mismatch: got {api_response['hydrus_version']}, expected {expected_version}"
  '';
}
