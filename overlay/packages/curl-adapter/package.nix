{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  requests,
  curl-cffi,
  pycurl,
}:

buildPythonPackage rec {
  pname = "curl_adapter";
  version = "1.0.0.post2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-sVpje78NHamLOCDfj4B/e6wPT5HWh0ARA4dr8Vn6geM=";
  };

  build-system = [ setuptools ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'pycurl==7.45.3' 'pycurl>=7.45.3'

    # Fix compatibility with urllib3 >= 2.6 which passes max_length to _decode()
    substituteInPlace curl_adapter/stream/response.py \
      --replace-fail 'def _decode(self, data, decode_content, flush_decoder):' \
                     'def _decode(self, data, decode_content, flush_decoder, max_length=None):' \
      --replace-fail 'return super()._decode(data, decode_content, flush_decoder)' \
                     'return super()._decode(data, decode_content, flush_decoder, max_length=max_length)'
  '';

  dependencies = [
    requests
    curl-cffi
    pycurl
  ];

  pythonImportsCheck = [ "curl_adapter" ];

  # There are no unit tests in the source tarball
  doCheck = false;

  meta = {
    description = "A curl HTTP adapter for the Python requests library with TLS fingerprint-changing capabilities";
    homepage = "https://github.com/el1s7/curl-adapter";
    license = lib.licenses.mit;
    maintainers = [ ];
    longDescription = ''
      A module that plugs directly into the Python requests library and
      replaces the default urllib3 HTTP adapter with cURL, equipped with
      TLS fingerprint-changing capabilities. Supports both curl_cffi and
      pycurl backends.
    '';
  };
}
