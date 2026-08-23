{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
  fetchurl,
  qt6,
  copyDesktopItems,
  makeDesktopItem,
  writableTmpDirAsHomeHook,
  ffmpeg_8,
  miniupnpc,
  pillow-jpegxl-plugin,
  sqlite,
}:
let
  mermaid = fetchurl {
    url = "https://unpkg.com/mermaid@11.17.0/dist/mermaid.min.js";
    hash = "sha256-jY4O7FbTqDtLPIf0IFCEVUbe6T6+GHXSEXwS5pR8DLM=";
  };
  iframe-worker = fetchurl {
    url = "https://unpkg.com/iframe-worker@1.0.4/shim/index.js";
    hash = "sha256-6OQS28/qm34xtf+iiNe2A1kV5xTFQvQXagzb4mL8lgk=";
  };
in
python3Packages.buildPythonApplication rec {
  pname = "hydrus";
  version = "684";
  pyproject = false;

  src = fetchFromGitHub {
    owner = "hydrusnetwork";
    repo = "hydrus";
    tag = "v${version}";
    hash = "sha256-8ZgvpyGqsY70utUreSgNg/dgAMMWJbt4aws8Jo2sOzU=";
  };

  nativeBuildInputs = [
    qt6.wrapQtAppsHook
    python3Packages.mkdocs-material
    copyDesktopItems
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtcharts
    qt6.qtmultimedia
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "io.github.hydrusnetwork.hydrus";
      exec = "hydrus-client";
      desktopName = "Hydrus Client";
      icon = "io.github.hydrusnetwork.hydrus";
      comment = meta.description;
      terminal = false;
      type = "Application";
      categories = [
        "FileTools"
        "Utility"
      ];
      startupWMClass = "Hydrus Client";
    })
  ];

  dependencies =
    with python3Packages;
    [
      beautifulsoup4
      cbor2
      chardet
      cryptography
      dateparser
      html5lib
      lxml
      lz4
      mpv
      numpy
      olefile
      opencv4
      pillow
      pillow-heif
      pillow-jpegxl-plugin
      psutil
      pympler
      pyopenssl
      pyqt6
      pyqt6-charts
      pyside6
      pysocks
      python-dateutil
      pyyaml
      qtpy
      requests
      send2trash
      service-identity
      show-in-file-manager
      tldextract
      twisted
    ]
    ++ python3Packages.twisted.optional-dependencies.tls
    ++ python3Packages.twisted.optional-dependencies.http2;

  nativeCheckInputs =
    (with python3Packages; [
      mock
      httmock
    ])
    ++ [
      writableTmpDirAsHomeHook
    ];

  outputs = [
    "out"
    "doc"
  ];

  installPhase = ''
    runHook preInstall

    # Move the hydrus module and related directories
    mkdir -p $out/${python3Packages.python.sitePackages}
    mv hydrus static $out/${python3Packages.python.sitePackages}
    ln -sf ${lib.getExe sqlite} $out/${python3Packages.python.sitePackages}/static/build_files/linux/sqlite3
    # Fix random files being marked with execute permissions
    chmod -x $out/${python3Packages.python.sitePackages}/static/*.{png,svg,ico}
    # Build docs
    mkdir -p .cache/plugin/privacy/assets/external/unpkg.com/{mermaid@11/dist,iframe-worker}
    ln -s ${mermaid} .cache/plugin/privacy/assets/external/unpkg.com/mermaid@11/dist/mermaid.min.js
    ln -s ${iframe-worker} .cache/plugin/privacy/assets/external/unpkg.com/iframe-worker/shim.js
    ln -s shim.js .cache/plugin/privacy/assets/external/unpkg.com/iframe-worker/shim
    mkdocs build -d help -f mkdocs-offline.yml
    mkdir -p $doc/share/doc
    mv help $doc/share/doc/hydrus

    # install the hydrus binaries
    mkdir -p $out/bin
    install -m0755 hydrus_server.py $out/bin/hydrus-server
    install -m0755 hydrus_client.py $out/bin/hydrus-client
    install -m0755 hydrus_test.py $out/bin/hydrus-test

    # desktop item
    mkdir -p "$out/share/icons/hicolor/scalable/apps"
    ln -s "$doc/share/doc/hydrus/assets/hydrus-white.svg" "$out/share/icons/hicolor/scalable/apps/io.github.hydrusnetwork.hydrus.svg"
  ''
  + ''
    runHook postInstall
  '';

  checkPhase = ''
    runHook preCheck

    export QT_QPA_PLATFORM=offscreen
    $out/bin/hydrus-test

    runHook postCheck
  '';

  # Tests crash even with __darwinAllowLocalNetworking enabled
  # hydrus.core.HydrusExceptions.DataMissing: That service was not found!
  doCheck = !stdenv.hostPlatform.isDarwin;

  dontWrapQtApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${qtWrapperArgs[@]}")
    makeWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        ffmpeg_8
        miniupnpc
      ]
    })
  '';

  meta = {
    description = "Danbooru-like image tagging and searching system for the desktop";
    mainProgram = "hydrus-client";
    license = lib.licenses.wtfpl;
    homepage = "https://hydrusnetwork.github.io/hydrus/";
    changelog = "https://github.com/hydrusnetwork/hydrus/releases/tag/${src.tag}";
  };
}
