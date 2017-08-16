{ python2 ? (import <nixpkgs> {}).python2
, stdenv ? (import <nixpkgs> {}).stdenv
, utillinux ? (import <nixpkgs> {}).utillinux
, yarn ? (import <nixpkgs> {}).yarn
, runCommand ? (import <nixpkgs> {}).runCommand
, callPackage ? (import <nixpkgs> {}).callPackage
, nodejs ? (import <nixpkgs> {}).nodejs-6_x
}:
let
  python = if nodejs ? python then nodejs.python else python2;
in

rec {
  inherit yarn;

  # Generates the yarn.nix from the yarn.lock file
  generateYarnNix = yarnLock: registryUsername: registrySecret:
    runCommand "yarn.nix" {} ''
      cat ${yarnLock} > yarn.lock.copy
      sed -i -e  "s/https:\/\/artifactory/https:\/\/${registryUsername}:${registrySecret}@artifactory/g" yarn.lock.copy
      ${yarn2nix}/bin/yarn2nix yarn.lock.copy > $out
      rm yarn.lock.copy
    '';

  loadOfflineCache = yarnNix:
    let
      pkg = callPackage yarnNix {};
    in
      pkg.offline_cache;

  buildYarnPackageDeps = {
    name,
    packageJson,
    yarnLock,
    registryUsername ? "",
    registrySecret ? "",
    yarnNix ? null,
    pkgConfig ? {},
    yarnFlags ? []
  }:
    let
      yarnNix_ =
        if yarnNix == null then (generateYarnNix yarnLock registryUsername registrySecret) else yarnNix;
      offlineCache =
        loadOfflineCache yarnNix_;
      extraBuildInputs = (stdenv.lib.flatten (builtins.map (key:
        pkgConfig.${key} . buildInputs or []
      ) (builtins.attrNames pkgConfig)));
      postInstall = (builtins.map (key:
        if (pkgConfig.${key} ? postInstall) then
          ''
            for f in $(find -L -path '*/node_modules/${key}' -type d); do
              (cd "$f" && (${pkgConfig.${key}.postInstall}))
            done
          ''
        else
          ""
      ) (builtins.attrNames pkgConfig));
    in
    stdenv.mkDerivation {
      name = "${name}-modules";

      phases = ["buildPhase"];
      buildInputs = [ yarn python nodejs ] ++ stdenv.lib.optional (stdenv.isLinux) utillinux ++ extraBuildInputs;

      buildPhase = ''
        # Yarn writes cache directories etc to $HOME.
        export HOME=`pwd`/yarn_home

        cp ${packageJson} ./package.json
        cp ${yarnLock} ./yarn.lock
        chmod +w ./yarn.lock

        yarn config --offline set yarn-offline-mirror ${offlineCache}

        # Do not look up in the registry, but in the offline cache.
        # TODO: Ask upstream to fix this mess.
        sed -i -E 's|^(\s*resolved\s*")https?://.*/|\1|' yarn.lock
        yarn install ${stdenv.lib.escapeShellArgs yarnFlags}

        ${stdenv.lib.concatStringsSep "\n" postInstall}

        mkdir $out
        mv node_modules $out/
        patchShebangs $out
      '';
    };

  buildYarnPackage = {
    name,
    src,
    packageJson,
    yarnLock,
    yarnNix ? null,
    extraBuildInputs ? [],
    pkgConfig ? {},
    extraYarnFlags ? [],
    yarnBuildCmd ? "",
    registryUsername ? "",
    registrySecret ? "",
    ...
  }@args:
    let
      yarnFlags = [ "--offline" "--frozen-lockfile" ] ++ extraYarnFlags;
      deps = buildYarnPackageDeps {
        inherit name packageJson yarnLock yarnNix pkgConfig yarnFlags registryUsername registrySecret;
      };
      npmPackageName = if stdenv.lib.hasAttr "npmPackageName" args
        then args.npmPackageName
        else (builtins.fromJSON (builtins.readFile "${src}/package.json")).name ;
      publishBinsFor = if stdenv.lib.hasAttr "publishBinsFor" args
        then args.publishBinsFor
        else [npmPackageName];
    in stdenv.mkDerivation rec {
      inherit name;
      inherit src;

      buildInputs = [ yarn python nodejs ] ++ stdenv.lib.optional (stdenv.isLinux) utillinux ++ extraBuildInputs;

      phases = ["unpackPhase" "yarnPhase" "fixupPhase"];

      yarnPhase = ''
        if [ -d node_modules ]; then
          echo "Node modules dir present. Removing."
          rm -rf node_modules
        fi

        if [ -d npm-packages-offline-cache ]; then
          echo "npm-pacakges-offline-cache dir present. Removing."
          rm -rf npm-packages-offline-cache
        fi
        echo "Creating node_modules..."
        mkdir $out
        mkdir -p $out/node_modules
        ln -s ${deps}/node_modules/* $out/node_modules/
        ln -s ${deps}/node_modules/.bin $out/node_modules/

        if [ -d $out/node_modules/${npmPackageName} ]; then
          echo "Error! There is already an ${npmPackageName} package in the top level node_modules dir!"
          exit 1
        fi

        echo "Creating the package directory structure..."
        mkdir $out/node_modules/${npmPackageName}/
        cp -r * $out/node_modules/${npmPackageName}/

        export HOME=`pwd`/yarn_home
        export PATH=$out/node_modules/.bin:$PATH
        export NODE_PATH=$out/node_modules
        mkdir node_modules
        ln -s $out/node_modules/* node_modules/
        ${yarnBuildCmd}
      '';

      preFixup = ''
        mkdir $out/bin
        node ${./nix/fixup_bin.js} $out ${stdenv.lib.concatStringsSep " " publishBinsFor}
      '';
  };

  yarn2nix = buildYarnPackage {
    name = "yarn2nix";
    src = ./.;
    packageJson = ./package.json;
    yarnLock = ./yarn.lock;
    yarnNix = ./yarn.nix;
  };
}
