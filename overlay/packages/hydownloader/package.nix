{
  lib,
  python3,
  fetchgit,
  ffmpeg,
  mkvtoolnix,
  gallery-dl,

  pkgs,
  writers,
  writeShellApplication,
  nix-update,
  curl,
  jq,
}:
let
  pythonPackages = python3.pkgs;
  importJob = builtins.fromJSON (builtins.readFile ./importJob.json);
  version = "0.66.0-unstable-373484d";
  src = fetchgit {
    url = "https://gitgud.io/thatfuckingbird/hydownloader";
    rev = "373484dc2134498eba71e490d2bda788e8850526";
    hash = "sha256-wHBJfBFdI+aoRmfaCz/ufghKZcKjCVO0cQRXTCpt9d8=";
  };
in
pythonPackages.buildPythonApplication {
  # Can't lift this assertion higher: prevents genImportJob from evaluating.
  assertions =
    assert lib.assertMsg (importJob.sourceHash == src.outputHash)
      "importJob.json is stale and needs to be regenerated; run `nix run .#hydownloader.passthru.genImportJob`";
    null;

  inherit version src;
  pname = "hydownloader";
  format = "pyproject";
  nativeBuildInputs = with pythonPackages; [
    poetry-core
    setuptools
  ];
  propagatedBuildInputs = with pythonPackages; [
    click
    bottle
    yt-dlp
    hydrus-api
    python-dateutil
    requests
    brotli
    gallery-dl
    pillow
    pysocks

    ffmpeg
    mkvtoolnix
  ];
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "poetry>=0.12" poetry-core \
      --replace-fail "poetry.masonry.api" "poetry.core.masonry.api"
  '';
  doCheck = false;
  postInstall = ''
    for cmd in hydownloader-importer hydownloader-anchor-exporter hydownloader-daemon hydownloader-tools hydl; do
      if [ ! -f "$out/bin/$cmd" ]; then
        echo "Error: $cmd script not found in output"
        exit 1
      fi
    done
  '';
  pythonImportsCheck = [ "hydownloader" ];
  passthru = {
    inherit importJob;
    genImportJob = writers.writePython3Bin "gen-import-job" { } ./genImportJob.py;
    updateScript = lib.getExe (writeShellApplication {
      name = "hydownloader-updater";
      runtimeInputs = [
        curl
        jq
        nix-update
      ];
      text = ''
        set -euo pipefail
        LATEST_COMMIT=$(curl -s "https://gitgud.io/api/v4/projects/thatfuckingbird%2Fhydownloader/repository/commits?per_page=1" | jq -r '.[0].id')
        SHORT_COMMIT=$(echo "$LATEST_COMMIT" | cut -c1-7)
        LATEST_VERSION=$(curl -s "https://gitgud.io/thatfuckingbird/hydownloader/-/raw/$LATEST_COMMIT/hydownloader/__init__.py" | sed -n "s/^__version__ = '\\(.*\\)'.*/\\1/p")
        PACKAGE_FILE="overlay/packages/hydownloader/package.nix"
        VERSION="$LATEST_VERSION-unstable-$SHORT_COMMIT"
        sed -i "s/rev = \"[^\"]*\";/rev = \"$LATEST_COMMIT\";/" "$PACKAGE_FILE"
        nix-update --flake hydownloader --version="$VERSION"
        eval "$(nix-build --no-out-link -A packages.${pkgs.system}.hydownloader.passthru.genImportJob)/bin/gen-import-job"
      '';
    });
  };
  meta = with lib; {
    description = "Download stuff like Hydrus does";
    homepage = "https://gitgud.io/thatfuckingbird/hydownloader";
    license = licenses.agpl3Plus;
    platforms = platforms.unix;
    mainProgram = "hydl";
  };
}
