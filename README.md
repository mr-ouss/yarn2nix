# yarn2nix
<img src="https://travis-ci.org/moretea/yarn2nix.svg?branch=master">

Converts `yarn.lock` files into nix expression.


1. Create a `default.nix` to build your application (see the example below)

## Example `default.nix`
 
  ```
    { nixpkgs ? <nixpkgs> 
    , registryUsername ? "USER"
    , registrySecret ? "KEY"
    , yarn_src ? ../yarn2nix
    }:
    with (import nixpkgs {});
    with (import yarn_src { inherit pkgs ; });
    rec {
      ui = buildYarnPackage {
        inherit registryUsername registrySecret;
        name = "my-project-ui";
        src = ./.;
        packageJson = ./package.json;
        yarnLock = ./yarn.lock;
        yarnBuildCmd = "NODE_ENV=prod webpack --progress --profile; cp -R dist $out";
      };
    }
   ```

## License
`yarn2nix` is released under the terms of the GPL-3.0 license.
