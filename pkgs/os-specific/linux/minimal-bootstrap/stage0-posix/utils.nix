{ lib
, stdenv
, callPackage
, fetchurl
, kaem
, kaem-unwrapped
, mescc-tools
, mescc-tools-extra
}:

let
  checkMeta = callPackage ../../../../stdenv/generic/check-meta.nix {
    inherit (stdenv) hostPlatform;
  };
in
rec {
  derivationWithMeta = attrs:
    let
      passthru = attrs.passthru or {};
      validity = checkMeta { inherit attrs; };
      inherit (validity) meta;
    in
    lib.extendDerivation
      validity.handled
      ({ inherit meta passthru; } // passthru)
      (derivation ({
        inherit (stdenv.buildPlatform) system;
        inherit (meta) name;
      } // (builtins.removeAttrs attrs [ "meta" "passthru" ])));

  writeTextFile =
    { name # the name of the derivation
    , text
    , executable ? false # run chmod +x ?
    , destination ? ""   # relative path appended to $out eg "/bin/foo"
    , allowSubstitutes ? false
    , preferLocalBuild ? true
    }:
    derivationWithMeta {
      inherit name text executable allowSubstitutes preferLocalBuild;
      passAsFile = [ "text" ];

      builder = kaem-unwrapped;
      args = [
        "--verbose"
        "--strict"
        "--file"
        (builtins.toFile "write-text-file.kaem" ''
          target=''${out}''${destination}
          if match x''${mkdirDestination} x1; then
            mkdir -p ''${out}''${destinationDir}
          fi
          cp ''${textPath} ''${target}
          if match x''${executable} x1; then
            chmod 555 ''${target}
          fi
        '')
      ];

      PATH = lib.makeBinPath [ mescc-tools-extra ];
      mkdirDestination = if builtins.dirOf destination == "." then "0" else "1";
      destinationDir = builtins.dirOf destination;
      inherit destination;
    };

  writeText = name: text: writeTextFile {inherit name text;};

  runCommand = name: env: buildCommand:
    derivationWithMeta ({
      inherit name;

      builder = "${kaem}/bin/kaem";
      args = [
        "--verbose"
        "--strict"
        "--file"
        (writeText "${name}-builder" buildCommand)
      ];

      PATH = lib.makeBinPath ((env.nativeBuildInputs or []) ++ [ kaem mescc-tools mescc-tools-extra ]);
    } // (builtins.removeAttrs env [ "nativeBuildInputs" ]));

}
