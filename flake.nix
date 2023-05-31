{
  description = "Bleeding edge Emacs overlay";

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-22.11";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-stable
    , flake-utils
    }: {
      # self: super: must be named final: prev: for `nix flake check` to be happy
      overlays = {
        default = final: prev: import ./overlays final prev;
        emacs = final: prev: import ./overlays/emacs.nix final prev;
        package = final: prev: import ./overlays/package.nix final prev;
      };
      # for backward compatibility, is safe to delete, not referenced anywhere
      overlay = self.overlays.default;
    } // flake-utils.lib.eachDefaultSystem (system: (
      let

        importPkgs = path: import path {
          inherit system;
          config.allowAliases = false;
          overlays = [ self.overlays.default ];
        };
        pkgs = importPkgs nixpkgs;

        inherit (pkgs) lib;
        overlayAttributes = lib.pipe (import ./. pkgs pkgs) [
          builtins.attrNames
          (lib.partition (n: lib.isDerivation pkgs.${n}))
        ];
        attributesToAttrset = attributes: lib.pipe attributes [
          (map (n: lib.nameValuePair n pkgs.${n}))
          lib.listToAttrs
        ];

      in
      {
        lib = attributesToAttrset overlayAttributes.wrong;
        packages = attributesToAttrset overlayAttributes.right;

        hydraJobs =
          let
          mkHydraJobs = pkgs: let
            mkEmacsSet = emacs: pkgs.recurseIntoAttrs (
              lib.filterAttrs
              (n: v: builtins.typeOf v == "set" && ! lib.isDerivation v)
              (pkgs.emacsPackagesFor emacs)
            );

          in {
              emacsen = {
                inherit (pkgs) emacsUnstable emacsUnstable-nox;
                inherit (pkgs) emacsGit emacsGit-nox;
                inherit (pkgs) emacsPgtk;
              };

              emacsen-cross =
                let
                  crossTargets = [ "aarch64-multiplatform" ];
                in
                lib.fold lib.recursiveUpdate { }
                  (builtins.map
                    (target:
                      let
                        targetPkgs = pkgs.pkgsCross.${target};
                      in
                      lib.mapAttrs' (name: job: lib.nameValuePair "${name}-${target}" job)
                        ({
                          inherit (targetPkgs) emacsUnstable emacsUnstable-nox;
                          inherit (targetPkgs) emacsGit emacsGit-nox;
                          inherit (targetPkgs) emacsPgtk;
                        }))
                    crossTargets);


              packages = mkEmacsSet pkgs.emacs;
              packages-unstable = mkEmacsSet pkgs.emacsUnstable;
            };

          in
          {
            "22.11" = mkHydraJobs (importPkgs nixpkgs-stable);
            "unstable" = mkHydraJobs pkgs;
          };

      }
    ));

}
