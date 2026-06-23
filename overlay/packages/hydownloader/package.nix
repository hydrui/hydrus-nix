{
  lib,
  python3,
  fetchgit,
  ffmpeg,
  mkvtoolnix,
  gallery-dl,
  hydrus-api,

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
  version = "0.77.0-unstable-b14ef56";
  src = fetchgit {
    url = "https://gitgud.io/thatfuckingbird/hydownloader";
    rev = "b14ef564976fb14288e9bee9f07cb7ad8abff570";
    hash = "sha256-ZJMUndEx63MuHryY7Jf6StEFX83cvw79sbW4u6jw3MU=";
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
  nativeBuildInputs = [
    pythonPackages.poetry-core
    pythonPackages.setuptools
  ];
  propagatedBuildInputs = [
    pythonPackages.cheroot
    pythonPackages.click
    pythonPackages.bottle
    pythonPackages.yt-dlp
    pythonPackages.yt-dlp-ejs
    pythonPackages.python-dateutil
    pythonPackages.requests
    pythonPackages.brotli
    pythonPackages.pillow
    pythonPackages.pysocks

    gallery-dl
    hydrus-api

    ffmpeg
    mkvtoolnix
  ];
  postPatch = ''
    sed -i -E 's/("[a-zA-Z0-9_-]+ *\()>=([0-9]+)\.[0-9]+\.[0-9]+[^)]*/\1>=\2.0.0/' pyproject.toml
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
