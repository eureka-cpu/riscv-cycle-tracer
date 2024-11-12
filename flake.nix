{
  description = "Risc0 zero-knowledge ELF analyzer.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, crane, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;

        craneLib = crane.mkLib pkgs;

        baseArgs = {
          src = craneLib.cleanCargoSource ./.;
        };

        # Returns true if the dependency requires `risc0-circuit-recursion` as part of its build.
        isRisc0CircuitRecursion = p: lib.hasPrefix
          "git+https://github.com/anagrambuild/risc0?branch=v1.0.1-bonsai-fix#189829d0b84d57e8928a85aa4fac60dd6ce45ea9"
          p.source;
        # Pre-pull the zkr file in order to apply in the postPatch phase for dependencies that require `risc0-circuit-recursion`.
        risc0CircuitRecursionPatch =
          let
            # see https://github.com/risc0/risc0/blob/v1.0.5/risc0/circuit/recursion/build.rs
            sha256Hash = "4e8496469e1efa00efb3630d261abf345e6b2905fb64b4f3a297be88ebdf83d2";
            recursionZkr = pkgs.fetchurl {
              name = "recursion_zkr.zip";
              url = "https://risc0-artifacts.s3.us-west-2.amazonaws.com/zkr/${sha256Hash}.zip";
              hash = "sha256-ToSWRp4e+gDvs2MNJhq/NF5rKQX7ZLTzope+iOvfg9I=";
            };
          in
          ''
            ln -sf ${recursionZkr} ./risc0/circuit/recursion/src/recursion_zkr.zip
          '';
        # Patch dependencies that require `risc0-circuit-recursion`.
        cargoVendorDir = craneLib.vendorCargoDeps (baseArgs // {
          overrideVendorGitCheckout = ps: drv:
            if lib.any (p: (isRisc0CircuitRecursion p)) ps then
            # Apply the patch for fetching the zkr zip file.
              drv.overrideAttrs
                {
                  patches = [ ./patches/risc0/v1.0.1-bonsai-fix/make-emu-instructions-pub.patch ];
                  postPatch = risc0CircuitRecursionPatch;
                }
            else
            # Nothing to change, leave the derivations as is.
              drv;
        });

        # Common arguments can be set here to avoid repeating them later
        # Note: changes here will rebuild all dependency crates
        commonArgs = {
          inherit cargoVendorDir;
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;

          buildInputs = [
            # Add additional build inputs here
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # Additional darwin specific inputs can be set here
            pkgs.libiconv
          ];
        };

        r0-zkvm-elf-analyzer = craneLib.buildPackage (commonArgs // {
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          # Additional environment variables or build phases/hooks can be set
          # here *without* rebuilding all dependency crates
          # MY_CUSTOM_VAR = "some value";
        });
      in
      {
        checks = {
          inherit r0-zkvm-elf-analyzer;
        };

        packages.default = r0-zkvm-elf-analyzer;

        apps.default = flake-utils.lib.mkApp {
          drv = r0-zkvm-elf-analyzer;
        };

        devShells.default = craneLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          # Additional dev-shell environment variables can be set directly
          # MY_CUSTOM_DEVELOPMENT_VAR = "something else";

          # Extra inputs can be added here; cargo and rustc are provided by default.
          packages = [
            # pkgs.ripgrep
          ];
        };
      });
}
