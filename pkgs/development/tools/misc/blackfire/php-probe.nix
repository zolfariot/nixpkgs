{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, php
, writeShellScript
, curl
, jq
, common-updater-scripts
}:

let
  phpMajor = lib.versions.majorMinor php.version;

  version = "1.88.1";

  hashes = {
    "x86_64-linux" = {
      system = "amd64";
      hash = {
        "8.1" = "0mgdg0wi6k049ax1q430pgdbpzlp0m3hlb22yakwpqdh8kwzvpzj";
        "8.2" = "0avkkz92pdyx0jwjwwjq0zgasc06m8gld7ahdwcw8p29z32l7igy";
      };
    };
    "i686-linux" = {
      system = "i386";
      hash = {
        "8.1" = "044vsm4dkn3bdl4jmfxjvfhi9wgrnk4aj89lrd6xms83immll9h1";
        "8.2" = "0vxzkc9j3sk246vsxjqdg3kxy40ygj4380vr3af91lgbfcyr6r09";
      };
    };
    "aarch64-linux" = {
      system = "arm64";
      hash = {
        "8.1" = "14nhvf91dc5jp24nd74jx49rkxv33c7fvl63i6mwzmn9f19zq90x";
        "8.2" = "0s7jg0811clf8wqkb6cfffhbi4nfn9jzh6mp7l2l72rxijaqiw5q";
      };
    };
    "aarch64-darwin" = {
      system = "arm64";
      hash = {
        "8.1" = "0df11ypxqixinzjlbwzcpsi0l8mrn2a7wv90zzp5qvgjiydpp4p0";
        "8.2" = "049sazyllipkr6rl5xhvyll9idng8qqz27qna04yjy4nlbz9qvh5";
      };
    };
    "x86_64-darwin" = {
      system = "amd64";
      hash = {
        "8.1" = "1jq7fwa6vc4r8jdfwcpcnva21z4k5vrwiy3a1gp2a528fg01ka1v";
        "8.2" = "12208zwn5qrk8xcmsfch46znhcs54bqxz4x07v38c62zvrv1734p";
      };
    };
  };

  makeSource = { system, phpMajor }:
    let
      isLinux = builtins.match ".+-linux" system != null;
    in
    assert !isLinux -> (phpMajor != null);
    fetchurl {
      url = "https://packages.blackfire.io/binaries/blackfire-php/${version}/blackfire-php-${if isLinux then "linux" else "darwin"}_${hashes.${system}.system}-php-${builtins.replaceStrings [ "." ] [ "" ] phpMajor}.so";
      hash = hashes.${system}.hash.${phpMajor};
    };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "php-blackfire";
  extensionName = "blackfire";
  inherit version;

  src = makeSource {
    system = stdenv.hostPlatform.system;
    inherit phpMajor;
  };

  nativeBuildInputs = lib.optionals stdenv.isLinux [
    autoPatchelfHook
  ];

  setSourceRoot = "sourceRoot=`pwd`";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -D ${finalAttrs.src} $out/lib/php/extensions/blackfire.so

    runHook postInstall
  '';

  passthru = {
    updateScript = writeShellScript "update-${finalAttrs.pname}" ''
      set -o errexit
      export PATH="${lib.makeBinPath [ curl jq common-updater-scripts ]}"
      NEW_VERSION=$(curl --silent https://blackfire.io/api/v1/releases | jq .probe.php --raw-output)

      if [[ "${version}" = "$NEW_VERSION" ]]; then
          echo "The new version same as the old version."
          exit 0
      fi

      for source in ${lib.concatStringsSep " " (builtins.attrNames finalAttrs.passthru.updateables)}; do
        update-source-version "$UPDATE_NIX_ATTR_PATH.updateables.$source" "0" "${lib.fakeSha256}"
        update-source-version "$UPDATE_NIX_ATTR_PATH.updateables.$source" "$NEW_VERSION"
      done
    '';

    # All sources for updating by the update script.
    updateables =
      let
        createName = path:
          builtins.replaceStrings [ "." ] [ "_" ] (lib.concatStringsSep "_" path);

        createSourceParams = path:
          let
            # The path will be either [«system» sha256], or [«system» sha256 «phpMajor» «zts»],
            # Let’s skip the sha256.
            rest = builtins.tail (builtins.tail path);
          in
          {
            system =
              builtins.head path;
            phpMajor =
              if builtins.length rest == 0
              then null
              else builtins.head rest;
          };

        createUpdateable = path: _value:
          lib.nameValuePair
            (createName path)
            (finalAttrs.self.overrideAttrs (attrs: {
              src = makeSource (createSourceParams path);
            }));

        # Filter out all attributes other than hashes.
        hashesOnly = lib.filterAttrsRecursive (name: _value: name != "system") hashes;
      in
      builtins.listToAttrs
        # Collect all leaf attributes (containing hashes).
        (lib.collect
          (attrs: attrs ? name)
          (lib.mapAttrsRecursive createUpdateable hashesOnly));
  };

  meta = {
    description = "Blackfire Profiler PHP module";
    homepage = "https://blackfire.io/";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ shyim ];
    platforms = [ "x86_64-linux" "aarch64-linux" "i686-linux" "x86_64-darwin" "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
