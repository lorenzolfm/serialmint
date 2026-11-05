{
  description = "serialmint: a Cashu mint on Postgres SERIALIZABLE";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      nixpkgs,
      rust-overlay,
      crane,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
      inherit (cargoToml.package) version;

      # Everything the flake makes, for one system.
      build =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };

          # Pinned in rust-toolchain.toml, which rustup reads too, so that every build and every run
          # of clippy is of one rust, whatever the system has. Read from there and not written again
          # here, so that the two cannot name two rusts.
          toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

          # crane builds the dependencies in a derivation of their own, so a change to our code
          # leaves it as it was: a cache hit, which CI restores from what main built.
          #
          # It writes TOML with remarshal, and not with crane-utils, a tool that it builds on
          # nixpkgs' rust: a second rust in what CI keeps of the store.
          craneLib = ((crane.mkLib pkgs).overrideToolchain toolchain).overrideScope (
            _: prev: { writeTOML = prev.writeTOMLViaRemarshal; }
          );

          # The source is filtered to what cargo reads, so editing the README is a cache hit.
          cargoFiles = pkgs.lib.fileset.unions [
            ./.cargo/config.toml
            ./src
            ./Cargo.toml
            ./Cargo.lock
          ];

          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = cargoFiles;
          };

          # clippy reads clippy.toml too, which no build does. It has a source of its own, so that
          # editing it rebuilds no package.
          lintSrc = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              cargoFiles
              ./clippy.toml
            ];
          };

          testSrc = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              cargoFiles
              ./.config/nextest.toml
            ];
          };

          # `dev` and the devshell build from this one list.
          buildTools = [
            toolchain
            pkgs.coreutils
            pkgs.stdenv.cc
          ];

          # What the tests run over, here and in `dev test`.
          testRun = "--workspace";

          # nextest fails a run with no tests. Remove the flag with the first test.
          nextestRun = "--no-tests=warn ${testRun}";

          # What the derivations share.
          common = {
            pname = "serialmint";
            inherit version src;
            strictDeps = true;
            cargoExtraArgs = "--locked";
            nativeCheckInputs = [ pkgs.cargo-nextest ];
          };

          deps = craneLib.buildDepsOnly common;

          # The tests run in the sandbox as part of the build, in the profile that ships, so a system
          # whose package builds is one whose package passes them.
          serialmint = craneLib.buildPackage (
            common
            // {
              src = testSrc;
              cargoArtifacts = deps;

              NEXTEST_SHOW_PROGRESS = "counter";
              checkPhaseCargoCommand = ''
                cargo nextest run --cargo-profile "$CARGO_PROFILE" --profile ci \
                  --test-threads "$NIX_BUILD_CORES" --locked ${nextestRun}
                cargoWithProfile test --doc --locked ${testRun}
              '';

              meta = {
                description = "A Cashu mint on Postgres SERIALIZABLE";
                homepage = "https://github.com/lorenzolfm/serialmint";
                mainProgram = "serialmint";
                platforms = systems;
              };
            }
          );

          # The run of clippy, which `dev clippy` makes in the tree you are editing and the check
          # below makes in the sandbox, for CI.
          clippyRun = "--all-targets --workspace";

          # Against the dependencies the build compiled, so it compiles none of them again. `-D
          # warnings`, as every lint in Cargo.toml is set to `warn`, so without it the run always
          # passes and gates nothing.
          clippy = craneLib.cargoClippy (
            common
            // {
              src = lintSrc;
              cargoArtifacts = deps;
              cargoClippyExtraArgs = "${clippyRun} -- -D warnings";
              # A check: nothing to test, and no `target/` that anything builds on.
              doCheck = false;
              doInstallCargoArtifacts = false;
            }
          );

          fmtRust = craneLib.cargoFmt {
            inherit (common) pname version;
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./Cargo.toml
                ./rustfmt.toml
                ./src
              ];
            };
            cargoExtraArgs = "--all";
            doInstallCargoArtifacts = false;
          };

          fmtNix =
            pkgs.runCommand "serialmint-fmt-nix"
              {
                nativeBuildInputs = [ pkgs.nixfmt ];
                src = pkgs.lib.fileset.toSource {
                  root = ./.;
                  fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
                };
              }
              ''
                find "$src" -name '*.nix' -exec nixfmt --check {} +
                touch "$out"
              '';

          # The project CLI, and the only place the recipes are written down. They live in
          # nix/dev/commands, one file for each command, as nix strings. A script on disk would be a
          # second way to run them, one that bypasses the pinned toolchain, so `nix develop` and
          # `nix run .#dev` are the only ways in. writeShellApplication runs shellcheck over each
          # command at build time.
          dev = import ./nix/dev {
            inherit
              pkgs
              toolchain
              buildTools
              clippyRun
              testRun
              nextestRun
              ;
            testTools = common.nativeCheckInputs;
          };
        in
        {
          inherit dev serialmint;

          checks = {
            inherit clippy fmtRust fmtNix;
          };

          formatter = pkgs.writeShellApplication {
            name = "serialmint-fmt";
            text = ''
              exec ${pkgs.lib.getExe dev} fmt "$@"
            '';
          };

          shell = pkgs.mkShell {
            packages = buildTools ++ [
              dev
              pkgs.cargo-nextest
            ];

            shellHook = ''
              echo "serialmint: rust $(rustc --version | cut -d' ' -f2); run 'dev help' for the command set"
            '';
          };
        };

      bySystem = nixpkgs.lib.genAttrs systems build;
    in
    {
      devShells = nixpkgs.lib.mapAttrs (_: built: { default = built.shell; }) bySystem;

      # `dev` is exposed so that `nix run .#dev -- clippy` works without a devshell, and so that CI
      # builds it, which runs shellcheck over the recipes.
      packages = nixpkgs.lib.mapAttrs (_: built: {
        inherit (built) dev serialmint;
        default = built.serialmint;
      }) bySystem;

      # clippy and the formatters, as CI runs them.
      checks = nixpkgs.lib.mapAttrs (_: built: built.checks) bySystem;

      formatter = nixpkgs.lib.mapAttrs (_: built: built.formatter) bySystem;
    };
}
