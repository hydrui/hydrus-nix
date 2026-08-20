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
  inherit (pkgs) lib;
  testApiKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  testImageHash = "9df84a3cff6f8a3f7d912c85d6d993f55085a4e29965b9f6f2a87336d972bd79";
  danbooruTestImageHash = "cad4cd142c4803234e9380591f58e5fed850fa50c06ebe22c94f61490d1844f5";
  danbooruHydlTestImageHash = "b4bdbff11a356a620ec6c7c08d4fb6affbb54b781e2c203cce05487689d2431b";
  caBundle = "/etc/ssl/certs/ca-certificates.crt";
  hydrusEnv = pkgs.writeText "hydrus-env" ''
    HYDRUS_DEFAULT_API_URL="http://127.0.0.1:45869"
    HYDRUS_DEFAULT_API_KEY="${testApiKey}"
    NIX_SSL_CERT_FILE="${caBundle}"
    REQUESTS_CA_BUNDLE="${caBundle}"
  '';
  wgDefault = "192.168.2.1";
  wgService = "192.168.2.2";
  ipDefault = "10.200.0.1";
  ipService = "10.200.0.2";
  testTlsCerts =
    let
      caConfig = pkgs.writeText "hydrus-test-ca.cnf" ''
        [req]
        distinguished_name = distinguished_name
        x509_extensions = extensions
        prompt = no

        [distinguished_name]
        commonName = hydrus-services-advanced test CA

        [extensions]
        basicConstraints = critical, CA:true
        keyUsage = critical, keyCertSign, cRLSign
        subjectKeyIdentifier = hash
      '';
      serverConfig = pkgs.writeText "hydrus-test-server.cnf" ''
        [req]
        distinguished_name = distinguished_name
        req_extensions = extensions
        prompt = no

        [distinguished_name]
        commonName = danbooru.donmai.us

        [extensions]
        basicConstraints = critical, CA:false
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @subject_alt_names

        [subject_alt_names]
        DNS.1 = danbooru.donmai.us
        DNS.2 = cdn.donmai.us
      '';
    in
    pkgs.runCommand "hydrus-services-advanced-tls-certs" { nativeBuildInputs = [ pkgs.openssl ]; } ''
      openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
        -config ${caConfig} -keyout ca.key -out ca.crt
      openssl req -new -newkey rsa:2048 -nodes \
        -config ${serverConfig} -keyout server.key -out server.csr
      openssl x509 -req -sha256 -days 36500 \
        -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -extfile ${serverConfig} -extensions extensions -out server.crt
      mkdir "$out"
      cp ca.crt server.crt server.key "$out/"
    '';
in
pkgs.testers.nixosTest {
  name = "hydrus-services-advanced";
  globalTimeout = 900;
  nodes = {
    client =
      { pkgs, ... }:
      {
        imports = [ self.outputs.nixosModules.default ];
        boot.kernel.sysctl."net.ipv4.ip_forward" = true;
        networking = {
          extraHosts = "${wgDefault} danbooru.donmai.us cdn.donmai.us";
          firewall.allowedTCPPorts = [
            443
            8080
          ];
        };
        security.pki.certificateFiles = [ "${testTlsCerts}/ca.crt" ];
        services.nginx = {
          enable = true;
          virtualHosts = {
            "${wgDefault}" = {
              listen = [
                {
                  addr = "0.0.0.0";
                  port = 8080;
                }
              ];
              root = ./testdata;
            };
            "danbooru.donmai.us" = {
              onlySSL = true;
              sslCertificate = "${testTlsCerts}/server.crt";
              sslCertificateKey = "${testTlsCerts}/server.key";
              locations = {
                "= /posts/5078" = {
                  alias = ./testdata/danbooru/post-5078.html;
                  extraConfig = "default_type text/html;";
                };
                "= /posts/99470.json" = {
                  alias = ./testdata/danbooru/post-99470.json;
                  extraConfig = "default_type application/json;";
                };
              };
            };
            "cdn.donmai.us" = {
              onlySSL = true;
              sslCertificate = "${testTlsCerts}/server.crt";
              sslCertificateKey = "${testTlsCerts}/server.key";
              locations = {
                "= /original/9a/b1/9ab12384f3be16cb49ea7f361e19fa29.gif".alias =
                  ./testdata/danbooru/9ab12384f3be16cb49ea7f361e19fa29.gif;
                "= /original/af/08/af08eb012b62258fc596cc17b8cade3a.jpg".alias =
                  ./testdata/danbooru/af08eb012b62258fc596cc17b8cade3a.jpg;
              };
            };
          };
        };
        services.hydrus = {
          client = {
            enable = true;
            environmentFile = hydrusEnv;
            initialDatabase = ./db-seed;
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
    client.wait_for_unit("nginx.service")
    client.wait_for_open_port(443, "${wgDefault}")
    client.wait_for_unit("hydrus-client.service")
    client.wait_for_open_port(45869, "${ipService}")

    with subtest("Disable guest Internet access"):
      client.succeed("ip route del default")
      client.fail("curl --connect-timeout 1 http://192.0.2.1")

    with subtest("Local HTTPS fixture is trusted"):
      client.succeed(
        "ip netns exec hydrus curl --fail https://danbooru.donmai.us/posts/5078 >/dev/null"
      )

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
      expected_version = ${toString self.outputs.packages.${system}.hydrus.version}
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
}
