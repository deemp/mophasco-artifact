{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    devshell = {
      url = "github:deemp/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.haskell-flake.flakeModule
        inputs.treefmt-nix.flakeModule
        inputs.devshell.flakeModule
      ];
      perSystem =
        {
          self',
          system,
          lib,
          config,
          pkgs,
          ...
        }:
        let
          ghcVersion = "9101";

          haskellPackages = pkgs.haskell.packages."ghc${ghcVersion}";

          # Our only Haskell project. You can have multiple projects, but this template
          # has only one.
          # See https://github.com/srid/haskell-flake/blob/master/example/flake.nix
          haskellProjects.default = {
            # To avoid unnecessary rebuilds, we filter projectRoot:
            # https://community.flake.parts/haskell-flake/local#rebuild
            projectRoot = builtins.toString (
              lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./src
                  ./mophasco.cabal
                  ./cabal.project
                ];
              }
            );

            basePackages = haskellPackages.override {
              # If need to remove dependency bounds
              # https://github.com/balsoft/lambda-launcher/blob/c4621b41989ff63b7241cf2a65335b4880f532e0/flake.nix#L17-L23
              overrides =
                self: super:
                let
                  # Simply use Hackage instead of overriding all-cabal-hashes (~2GB unpacked)
                  # https://github.com/NixOS/nixpkgs/blob/21d55dd87e040944379bfe0574d9e24caf3dec20/pkgs/development/haskell-modules/make-package-set.nix#L28
                  packageFromHackage =
                    pkg: ver: sha256:
                    super.callHackageDirect { inherit pkg ver sha256; } { };
                in
                {
                  alex = packageFromHackage "alex" "3.5.2.0" "sha256-hTkBDe30UkUVx1MTa4BjpYK5nyYlULCylZEniW6sSnA=";
                  happy = packageFromHackage "happy" "2.1.5" "sha256-rM6CpEFZRen8ogFIOGjKEmUzYPT7dor/SQVVL8RzLwE=";

                  ## needed by happy

                  happy-lib =
                    packageFromHackage "happy-lib" "2.1.5"
                      "sha256-XzWzDiJUBTxuliE5RN6MOeIdKzQQD1NurDrtZ/dW4OQ=";
                };
            };

            settings =
              let
                default = {
                  haddock = false;
                  check = false;
                };
              in
              {
                free-foil-stlc = default // {
                  extraBuildTools = with devTools; [
                    alex
                    happy
                  ];
                };

                happy = default;

                ## needed by happy

                happy-lib = default;
              };

            # Development shell configuration
            devShell = {
              hlsCheck.enable = false;
              hoogle = false;
              tools = hp: {
                cabal-install = null;
                hlint = null;
                haskell-language-server = null;
                ghcid = null;
              };
            };

            # What should haskell-flake add to flake outputs?
            autoWire = [
              "packages"
              "apps"
              "checks"
            ]; # Wire all but the devShell
          };

          devTools =
            let
              output = config.haskellProjects.default.outputs;
              wrapTool =
                pkgsName: pname: flags:
                let
                  pkg = pkgs.${pkgsName};
                in
                pkgs.symlinkJoin {
                  name = pname;
                  paths = [ pkg ];
                  meta = pkg.meta;
                  version = pkg.version;
                  buildInputs = [ pkgs.makeWrapper ];
                  postBuild = ''
                    wrapProgram $out/bin/${pname} \
                      --add-flags "${flags}"
                  '';
                };
            in
            {
              inherit (output.finalPackages) alex happy;
              
              cabal = wrapTool "cabal-install" "cabal" "-v0 -fnix";

              ghc = builtins.head (
                builtins.filter (
                  x: pkgs.lib.attrsets.isDerivation x && pkgs.lib.strings.hasPrefix "ghc-" x.name
                ) output.devShell.nativeBuildInputs
              );

              inherit (haskellPackages) haskell-language-server;
            };

          # Auto formatters. This also adds a flake check to ensure that the
          # source tree was auto formatted.
          treefmt.config = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              shellcheck.enable = true;
              fourmolu = {
                enable = true;
                ghcOpts = [
                  "NoPatternSynonyms"
                  "CPP"
                ];
              };
              prettier.enable = true;
            };
            settings = {
              global.excludes = [ ];
            };
          };

          devshells = {
            default = {
              commands = {
                tools = [
                  {
                    expose = true;
                    packages = devTools;
                  }
                ];

                scripts = [
                  {
                    prefix = "nix fmt";
                    help = "Format files.";
                  }
                ];
              };
            };
          };
        in
        {
          inherit treefmt devshells haskellProjects;
          legacyPackages = {
            inherit (config.haskellProjects.default) basePackages;
          };
        };
    };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };
}
