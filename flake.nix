{
  description = "serialmint: a Cashu mint on Postgres SERIALIZABLE";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    rust-overlay,
    crane,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem = {
        system,
        pkgs,
        ...
      }: let
        craneLib =
          (crane.mkLib pkgs).overrideToolchain (p:
            p.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml);

        # The gates build with the toolchain file as it is written: minimal. The dev shell adds
        # rust-src, because rust-analyzer reads the documentation of the standard library from those
        # sources. `override` replaces the component list, so read the list from the file.
        toolchainFile = builtins.fromTOML (builtins.readFile ./rust-toolchain.toml);

        craneLibDev = (crane.mkLib pkgs).overrideToolchain (p:
          (p.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
            extensions = toolchainFile.toolchain.components ++ ["rust-src"];
          });

        src = craneLib.cleanCargoSource ./.;

        commonArgs = {
          inherit src;
          strictDeps = true;
        };

        # Build only the dependencies, so a change to the crate does not build them again.
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        # The test gate runs in the dev profile, as `cargo test` does in the dev shell. The release
        # profile turns off overflow checks and `debug_assert!`. The dev profile needs its own build
        # of the dependencies.
        devArgs =
          commonArgs
          // {
            CARGO_PROFILE = "dev";
            cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {CARGO_PROFILE = "dev";});
          };

        serialmint = craneLib.buildPackage (commonArgs
          // {
            inherit cargoArtifacts;

            # The test gate runs the tests. Do not run them two times.
            doCheck = false;

            meta = {
              description = "A Cashu mint on Postgres SERIALIZABLE";
              homepage = "https://github.com/lorenzolfm/serialmint";
              mainProgram = "serialmint";
              platforms = pkgs.lib.platforms.unix;
            };
          });

        # One derivation for each gate. CI builds them in parallel, and `nix flake check` runs all
        # of them.
        gates = {
          inherit serialmint;

          serialmint-clippy = craneLib.cargoClippy (commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

          # nextest fails a run with no tests. Remove this flag with the first test.
          serialmint-test = craneLib.cargoNextest (devArgs
            // {
              cargoNextestExtraArgs = "--no-tests=warn";
            });

          serialmint-fmt = craneLib.cargoFmt {inherit src;};

          # `advisories` needs the network, so a sandboxed gate cannot run it.
          serialmint-deny = craneLib.cargoDeny {
            inherit src;
            cargoDenyChecks = "bans sources";
          };
        };
      in {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };

        checks = gates;

        # Give each gate a package name, so CI can build one gate with `nix build .#<gate>`.
        packages =
          gates
          // {
            default = serialmint;
          };

        apps.default = {
          type = "app";
          program = "${pkgs.lib.getExe serialmint}";
          meta.description = "A Cashu mint on Postgres SERIALIZABLE";
        };

        devShells.default = craneLibDev.devShell {
          packages = [pkgs.cargo-nextest pkgs.cargo-mutants pkgs.cargo-deny];
        };

        formatter = pkgs.alejandra;
      };
    };
}
