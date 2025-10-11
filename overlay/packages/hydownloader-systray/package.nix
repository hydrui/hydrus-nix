{
  lib,
  stdenv,
  fetchFromGitLab,
  cmake,
  qt6,
  makeDesktopItem,
  copyDesktopItems,

  writeShellApplication,
  curl,
  jq,
  nix-update,
}:

stdenv.mkDerivation {
  pname = "hydownloader-systray";
  version = "0-unstable-2025-07-28-2053ace";

  src = fetchFromGitLab {
    domain = "gitgud.io";
    owner = "thatfuckingbird";
    repo = "hydownloader-systray";
    rev = "2053acef01cfd0ff464a3d55536da334dc350366";
    hash = "sha256-iHp7ONJuLc18j5uLxSmt7i91bXI7pxA/08ksg875gsc=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    copyDesktopItems
  ];

  buildInputs = [
    qt6.qtbase
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "hydownloader-systray";
      exec = "hydownloader-systray";
      desktopName = "hydownloader systray";
      icon = "hydownloader-systray";
      comment = "Systray for hydownloader";
      terminal = false;
      type = "Application";
      categories = [
        "Application"
        "FileTools"
      ];
    })
  ];

  postPatch = ''
    # Allow a global config file for convenience
    substituteInPlace src/hydownloader-systray/main.cpp \
      --replace-fail 'defaultSettingsFilename = QCoreApplication::applicationDirPath() + "/settings.ini"' \
                     'defaultSettingsFilename = "/etc/hydownloader-systray/settings.ini"'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 hydownloader-systray $out/bin/hydownloader-systray
    install -Dm644 $src/icon/hydownloader-systray.png $out/share/icons/hicolor/256x256/apps/hydownloader-systray.png
    runHook postInstall
  '';

  passthru = {
    updateScript = lib.getExe (writeShellApplication {
      name = "hydownloader-updater";
      runtimeInputs = [
        curl
        jq
        nix-update
      ];
      text = ''
        set -euo pipefail
        LATEST_COMMIT_META=$(curl -s "https://gitgud.io/api/v4/projects/thatfuckingbird%2Fhydownloader-systray/repository/commits?per_page=1")
        LATEST_COMMIT=$(echo "$LATEST_COMMIT_META" | jq -r '.[0].id')
        COMMIT_DATE=$(echo "$LATEST_COMMIT_META" | jq -r '.[0].created_at' | cut -c1-10)
        SHORT_COMMIT=$(echo "$LATEST_COMMIT" | cut -c1-7)
        PACKAGE_FILE="overlay/packages/hydownloader-systray/package.nix"
        VERSION="0-unstable-$COMMIT_DATE-$SHORT_COMMIT"
        sed -i "s/rev = \"[^\"]*\";/rev = \"$LATEST_COMMIT\";/" "$PACKAGE_FILE"
        nix-update --flake hydownloader-systray --version="$VERSION"
      '';
    });
  };

  meta = with lib; {
    description = "Remote management GUI for hydownloader";
    homepage = "https://gitgud.io/thatfuckingbird/hydownloader-systray";
    license = licenses.agpl3Plus;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "hydownloader-systray";
  };
}
