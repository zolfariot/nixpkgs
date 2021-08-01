{ stdenv, lib, llvmPackages, gnChromium, ninja, which, nodejs, fetchpatch, fetchurl

# default dependencies
, gnutar, bzip2, flac, speex, libopus
, libevent, expat, libjpeg, snappy
, libpng, libcap
, xdg-utils, yasm, nasm, minizip, libwebp
, libusb1, pciutils, nss, re2

, python2, python3, perl, pkg-config
, nspr, systemd, libkrb5
, util-linux, alsa-lib
, bison, gperf
, glib, gtk3, dbus-glib
, glibc
, libXScrnSaver, libXcursor, libXtst, libxshmfence, libGLU, libGL
, protobuf, speechd, libXdamage, cups
, ffmpeg, libxslt, libxml2, at-spi2-core
, jre8
, pipewire
, libva
, libdrm, wayland, mesa, libxkbcommon # Ozone
, curl

# optional dependencies
, libgcrypt ? null # gnomeSupport || cupsSupport

# package customization
, gnomeSupport ? false, gnome2 ? null
, gnomeKeyringSupport ? false, libgnome-keyring3 ? null
, proprietaryCodecs ? true
, cupsSupport ? true
, pulseSupport ? false, libpulseaudio ? null
, ungoogled ? false, ungoogled-chromium

, channel
, upstream-info
}:

buildFun:

with lib;

let
  jre = jre8; # TODO: remove override https://github.com/NixOS/nixpkgs/pull/89731
  python2WithPackages = python2.withPackages(ps: with ps; [
    ply jinja2 setuptools
  ]);
  python3WithPackages = python3.withPackages(ps: with ps; [
    ply jinja2 setuptools
  ]);

  # The additional attributes for creating derivations based on the chromium
  # source tree.
  extraAttrs = buildFun base;

  githubPatch = { commit, sha256, revert ? false }: fetchpatch {
    url = "https://github.com/chromium/chromium/commit/${commit}.patch";
    inherit sha256 revert;
  };

  mkGnFlags =
    let
      # Serialize Nix types into GN types according to this document:
      # https://source.chromium.org/gn/gn/+/master:docs/language.md
      mkGnString = value: "\"${escape ["\"" "$" "\\"] value}\"";
      sanitize = value:
        if value == true then "true"
        else if value == false then "false"
        else if isList value then "[${concatMapStringsSep ", " sanitize value}]"
        else if isInt value then toString value
        else if isString value then mkGnString value
        else throw "Unsupported type for GN value `${value}'.";
      toFlag = key: value: "${key}=${sanitize value}";
    in attrs: concatStringsSep " " (attrValues (mapAttrs toFlag attrs));

  # https://source.chromium.org/chromium/chromium/src/+/master:build/linux/unbundle/replace_gn_files.py
  gnSystemLibraries = lib.optionals (!chromiumVersionAtLeast "93") [
    "ffmpeg"
    "snappy"
  ] ++ [
    "flac"
    "libjpeg"
    "libpng"
    "libwebp"
    "libxslt"
    "opus"
    "zlib"
  ];

  opusWithCustomModes = libopus.override {
    withCustomModes = true;
  };

  defaultDependencies = [
    (libpng.override { apngSupport = false; }) # https://bugs.chromium.org/p/chromium/issues/detail?id=752403
    bzip2 flac speex opusWithCustomModes
    libevent expat libjpeg snappy
    libcap
    xdg-utils minizip libwebp
    libusb1 re2
    ffmpeg libxslt libxml2
    nasm
  ];

  # build paths and release info
  packageName = extraAttrs.packageName or extraAttrs.name;
  buildType = "Release";
  buildPath = "out/${buildType}";
  libExecPath = "$out/libexec/${packageName}";

  warnObsoleteVersionConditional = min-version: result:
    let ungoogled-version = (importJSON ./upstream-info.json).ungoogled-chromium.version;
    in warnIf (versionAtLeast ungoogled-version min-version) "chromium: ungoogled version ${ungoogled-version} is newer than a conditional bounded at ${min-version}. You can safely delete it."
      result;
  chromiumVersionAtLeast = min-version:
    let result = versionAtLeast upstream-info.version min-version;
    in  warnObsoleteVersionConditional min-version result;
  versionRange = min-version: upto-version:
    let inherit (upstream-info) version;
        result = versionAtLeast version min-version && versionOlder version upto-version;
    in warnObsoleteVersionConditional upto-version result;

  ungoogler = ungoogled-chromium {
    inherit (upstream-info.deps.ungoogled-patches) rev sha256;
  };

  base = rec {
    name = "${packageName}-unwrapped-${version}";
    inherit (upstream-info) version;
    inherit packageName buildType buildPath;

    src = fetchurl {
      url = "https://commondatastorage.googleapis.com/chromium-browser-official/chromium-${version}.tar.xz";
      inherit (upstream-info) sha256;
    };

    nativeBuildInputs = [
      ninja pkg-config
      python2WithPackages python3WithPackages perl nodejs
      gnutar which
      llvmPackages.bintools
    ];

    buildInputs = defaultDependencies ++ [
      nspr nss systemd
      util-linux alsa-lib
      bison gperf libkrb5
      glib gtk3 dbus-glib
      libXScrnSaver libXcursor libXtst libxshmfence libGLU libGL
      mesa # required for libgbm
      pciutils protobuf speechd libXdamage at-spi2-core
      jre
      pipewire
      libva
      libdrm wayland mesa.drivers libxkbcommon
      curl
    ] ++ optional gnomeKeyringSupport libgnome-keyring3
      ++ optionals gnomeSupport [ gnome2.GConf libgcrypt ]
      ++ optionals cupsSupport [ libgcrypt cups ]
      ++ optional pulseSupport libpulseaudio;

    patches = [
      ./patches/no-build-timestamps.patch # Optional patch to use SOURCE_DATE_EPOCH in compute_build_timestamp.py (should be upstreamed)
      ./patches/widevine-79.patch # For bundling Widevine (DRM), might be replaceable via bundle_widevine_cdm=true in gnFlags
      # Fix the build by adding a missing dependency (s. https://crbug.com/1197837):
      ./patches/fix-missing-atspi2-dependency.patch
      ./patches/closure_compiler-Use-the-Java-binary-from-the-system.patch
    ] ++ lib.optionals (chromiumVersionAtLeast "93") [
      # We need to revert this patch to build M93 with LLVM 12.
      (githubPatch {
        # Reland "Replace 'blacklist' with 'ignorelist' in ./tools/msan/."
        commit = "9d080c0934b848ee4a05013c78641e612fcc1e03";
        sha256 = "1bxdhxmiy6h4acq26lq43x2mxx6rawmfmlgsh5j7w8kyhkw5af0c";
        revert = true;
      })
    ];

    postPatch = ''
      # remove unused third-party
      for lib in ${toString gnSystemLibraries}; do
        if [ -d "third_party/$lib" ]; then
          find "third_party/$lib" -type f \
            \! -path "third_party/$lib/chromium/*" \
            \! -path "third_party/$lib/google/*" \
            \! -path "third_party/harfbuzz-ng/utils/hb_scoped.h" \
            \! -regex '.*\.\(gn\|gni\|isolate\)' \
            -delete
        fi
      done

      # Required for patchShebangs (unsupported interpreter directive, basename: invalid option -- '*', etc.):
      substituteInPlace native_client/SConstruct --replace "#! -*- python -*-" ""
      if [ -e third_party/harfbuzz-ng/src/src/update-unicode-tables.make ]; then
        substituteInPlace third_party/harfbuzz-ng/src/src/update-unicode-tables.make \
          --replace "/usr/bin/env -S make -f" "/usr/bin/make -f"
      fi
      chmod -x third_party/webgpu-cts/src/tools/deno

      # We want to be able to specify where the sandbox is via CHROME_DEVEL_SANDBOX
      substituteInPlace sandbox/linux/suid/client/setuid_sandbox_host.cc \
        --replace \
          'return sandbox_binary;' \
          'return base::FilePath(GetDevelSandboxPath());'

      substituteInPlace services/audio/audio_sandbox_hook_linux.cc \
        --replace \
          '/usr/share/alsa/' \
          '${alsa-lib}/share/alsa/' \
        --replace \
          '/usr/lib/x86_64-linux-gnu/gconv/' \
          '${glibc}/lib/gconv/' \
        --replace \
          '/usr/share/locale/' \
          '${glibc}/share/locale/'

      sed -i -e 's@"\(#!\)\?.*xdg-@"\1${xdg-utils}/bin/xdg-@' \
        chrome/browser/shell_integration_linux.cc

      sed -i -e '/lib_loader.*Load/s!"\(libudev\.so\)!"${lib.getLib systemd}/lib/\1!' \
        device/udev_linux/udev?_loader.cc

      sed -i -e '/libpci_loader.*Load/s!"\(libpci\.so\)!"${pciutils}/lib/\1!' \
        gpu/config/gpu_info_collector_linux.cc

      # Allow to put extensions into the system-path.
      sed -i -e 's,/usr,/run/current-system/sw,' chrome/common/chrome_paths.cc

      patchShebangs .
      # use our own nodejs
      mkdir -p third_party/node/linux/node-linux-x64/bin
      ln -s "$(command -v node)" third_party/node/linux/node-linux-x64/bin/node

      # Allow building against system libraries in official builds
      sed -i 's/OFFICIAL_BUILD/GOOGLE_CHROME_BUILD/' tools/generate_shim_headers/generate_shim_headers.py

    '' + optionalString stdenv.isAarch64 ''
      substituteInPlace build/toolchain/linux/BUILD.gn \
        --replace 'toolprefix = "aarch64-linux-gnu-"' 'toolprefix = ""'
    '' + optionalString ungoogled ''
      ${ungoogler}/utils/prune_binaries.py . ${ungoogler}/pruning.list || echo "some errors"
      ${ungoogler}/utils/patches.py . ${ungoogler}/patches
      ${ungoogler}/utils/domain_substitution.py apply -r ${ungoogler}/domain_regex.list -f ${ungoogler}/domain_substitution.list -c ./ungoogled-domsubcache.tar.gz .
    '';

    gnFlags = mkGnFlags ({
      # Main build and toolchain settings:
      is_official_build = true;
      custom_toolchain = "//build/toolchain/linux/unbundle:default";
      host_toolchain = "//build/toolchain/linux/unbundle:default";
      use_sysroot = false;
      system_wayland_scanner_path = "${wayland}/bin/wayland-scanner";
      treat_warnings_as_errors = false;
      clang_use_chrome_plugins = false;
      blink_symbol_level = 0;
      symbol_level = 0;
      fieldtrial_testing_like_official_build = true;

      # Google API key, see: https://www.chromium.org/developers/how-tos/api-keys
      # Note: The API key is for NixOS/nixpkgs use ONLY.
      # For your own distribution, please get your own set of keys.
      google_api_key = "AIzaSyDGi15Zwl11UNe6Y-5XW_upsfyw31qwZPI";

      # Optional features:
      use_cups = cupsSupport;
      use_gio = gnomeSupport;
      use_gnome_keyring = gnomeKeyringSupport;

      # Feature overrides:
      # Native Client support was deprecated in 2020 and support will end in June 2021:
      enable_nacl = false;
      # Enabling the Widevine component here doesn't affect whether we can
      # redistribute the chromium package; the Widevine component is either
      # added later in the wrapped -wv build or downloaded from Google:
      enable_widevine = true;
      # Provides the enable-webrtc-pipewire-capturer flag to support Wayland screen capture:
      rtc_use_pipewire = true;
    } // optionalAttrs proprietaryCodecs {
      # enable support for the H.264 codec
      proprietary_codecs = true;
      enable_hangout_services_extension = true;
      ffmpeg_branding = "Chrome";
    } // optionalAttrs pulseSupport {
      use_pulseaudio = true;
      link_pulseaudio = true;
    } // optionalAttrs ungoogled {
      chrome_pgo_phase = 0;
      enable_hangout_services_extension = false;
      enable_js_type_check = false;
      enable_mdns = false;
      enable_nacl_nonsfi = false;
      enable_one_click_signin = false;
      enable_reading_list = false;
      enable_remoting = false;
      enable_reporting = false;
      enable_service_discovery = false;
      exclude_unwind_tables = true;
      google_api_key = "";
      google_default_client_id = "";
      google_default_client_secret = "";
      safe_browsing_mode = 0;
      use_official_google_api_keys = false;
      use_unofficial_version_number = false;
    } // (extraAttrs.gnFlags or {}));

    configurePhase = ''
      runHook preConfigure

      # This is to ensure expansion of $out.
      libExecPath="${libExecPath}"
      ${python2}/bin/python2 build/linux/unbundle/replace_gn_files.py --system-libraries ${toString gnSystemLibraries}
      ${gnChromium}/bin/gn gen --args=${escapeShellArg gnFlags} out/Release | tee gn-gen-outputs.txt

      # Fail if `gn gen` contains a WARNING.
      grep -o WARNING gn-gen-outputs.txt && echo "Found gn WARNING, exiting nix build" && exit 1

      runHook postConfigure
    '';

    # Don't spam warnings about unknown warning options. This is useful because
    # our Clang is always older than Chromium's and the build logs have a size
    # of approx. 25 MB without this option (and this saves e.g. 66 %).
    NIX_CFLAGS_COMPILE = "-Wno-unknown-warning-option";

    buildPhase = let
      buildCommand = target: ''
        ninja -C "${buildPath}" -j$NIX_BUILD_CORES -l$NIX_BUILD_CORES "${target}"
        (
          source chrome/installer/linux/common/installer.include
          PACKAGE=$packageName
          MENUNAME="Chromium"
          process_template chrome/app/resources/manpage.1.in "${buildPath}/chrome.1"
        )
      '';
      targets = extraAttrs.buildTargets or [];
      commands = map buildCommand targets;
    in concatStringsSep "\n" commands;

    postFixup = ''
      # Make sure that libGLESv2 is found by dlopen (if using EGL).
      chromiumBinary="$libExecPath/$packageName"
      origRpath="$(patchelf --print-rpath "$chromiumBinary")"
      patchelf --set-rpath "${libGL}/lib:$origRpath" "$chromiumBinary"
    '';

    passthru = {
      updateScript = ./update.py;
      chromiumDeps = {
        gn = gnChromium;
      };
    };
  };

# Remove some extraAttrs we supplied to the base attributes already.
in stdenv.mkDerivation (base // removeAttrs extraAttrs [
  "name" "gnFlags" "buildTargets"
] // { passthru = base.passthru // (extraAttrs.passthru or {}); })
