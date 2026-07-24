{
  lib,
  buildPythonPackage,
  pytestCheckHook,
  pythonImportsCheckHook,
  fetchFromGitHub,
  rustPlatform,
  maturin,
  cmake,
  packaging,
  pillow,
  numpy,
  py3exiv2,
}:

buildPythonPackage rec {
  pname = "pillow-jpegxl-plugin";
  version = "1.3.8";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Isotr0py";
    repo = "pillow-jpegxl-plugin";
    tag = "v${version}";
    hash = "sha256-S9Im6b8zHeGi5TWpInUngKbjs/QA4bdgp1vc21B33ss=";
  };

  postPatch = ''
    ln -s '${./Cargo.lock}' Cargo.lock
  '';

  build-system = [ maturin ];

  nativeBuildInputs = with rustPlatform; [
    cargoSetupHook
    maturinBuildHook
    cmake
  ];

  dontUseCmakeConfigure = true;

  cargoDeps = rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };

  dependencies = [
    packaging
    pillow
  ];

  doCheck = false;

  nativeCheckInputs = [
    pytestCheckHook
    pythonImportsCheckHook
    numpy
    py3exiv2
  ];

  pythonImportsCheck = [
    "pillow_jxl"
  ];

  meta = {
    description = "Pillow plugin that adds support for JPEG XL files";
    homepage = "https://github.com/Isotr0py/pillow-jpegxl-plugin";
    license = lib.licenses.gpl3Only;
  };
}
