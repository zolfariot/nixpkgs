{ lib
, mkDerivation
, cmake
, corrosion
, extra-cmake-modules
, kconfig
, kcoreaddons
, kdbusaddons
, ki18n
, kirigami-addons
, kirigami2
, knotifications
, kpurpose
, kwindowsystem
, qtfeedback
, qtquickcontrols2
, qqc2-desktop-style
, qtwebengine
, rustPlatform
, srcs

# These must be updated in tandem with package updates.
# Values are provided as callPackage inputs to enable easier overrides through overlays.
, cargoShaForVersion ? "23.04.1"
, cargoSha256 ? "sha256-whMfpElpFB7D+dHHJrbwINFL4bVpHTlcZX+mdBfiqEE="
}:

mkDerivation rec {
  pname = "angelfish";

  cargoDeps = rustPlatform.fetchCargoTarball {
    src = srcs.angelfish.src;
    name = "${pname}-${srcs.angelfish.version}";
    # Fail at build time so this gets caught by nixpkgs-review.
    sha256 = if cargoShaForVersion == srcs.angelfish.version then cargoSha256 else lib.fakeHash;
  };

  nativeBuildInputs = [
    cmake
    corrosion
    extra-cmake-modules
  ] ++ (with rustPlatform; [
    cargoSetupHook
    rust.cargo
    rust.rustc
  ]);

  buildInputs = [
    kconfig
    kcoreaddons
    kdbusaddons
    ki18n
    kirigami-addons
    kirigami2
    knotifications
    kpurpose
    kwindowsystem
    qtfeedback
    qtquickcontrols2
    qqc2-desktop-style
    qtwebengine
  ];

  meta = with lib; {
    description = "Web browser for Plasma Mobile";
    homepage = "https://invent.kde.org/plasma-mobile/angelfish";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ dotlambda ];
  };
}
