{
  description = "serialmint: a Cashu mint";

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
      ];

      # Everything the flake makes, for one system.
      build =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };

          # Read from rust-toolchain.toml and not written again here, so that the flake and rustup
          # cannot name two rusts.
          toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

          craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

          # A source of these files alone, so that editing any other file rebuilds nothing that reads
          # it.
          sourceOf =
            files:
            pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions files;
            };

          # What a build of the package reads. craneLib.cleanCargoSource would also keep every other
          # .toml, so that editing one would rebuild the package. cargo finds build.rs and
          # .cargo/config.toml by their names alone, so that leaving one out would change the build
          # with no error.
          cargoFiles = [
            ./src
            ./Cargo.toml
            ./Cargo.lock
            (pkgs.lib.fileset.maybeMissing ./build.rs)
            (pkgs.lib.fileset.maybeMissing ./.cargo/config.toml)
          ];

          # What the derivations share.
          common = {
            src = sourceOf cargoFiles;
            strictDeps = true;
            cargoExtraArgs = "--locked";
          };

          serialmint = craneLib.buildPackage (
            common
            // {
              # The `test` and `doctest` gates run them. Building the package will not need Postgres
              # and LND, once the tests do.
              doCheck = false;
            }
          );

          # The tests run in the dev profile, which the test profile of `dev test` inherits, since
          # the release profile turns off `debug_assert!`. So they need a build of the dependencies
          # of their own.
          #
          # The gates keep no target. Nothing reads it, and a gate that fails has no output, so that
          # the JUnit of a failed run could not come from there.
          devProfile =
            let
              args = common // {
                CARGO_PROFILE = "dev";
              };
            in
            args
            // {
              cargoArtifacts = craneLib.buildDepsOnly args;
              doInstallCargoArtifacts = false;
            };

          # The run of clippy, which `dev clippy` makes in the tree you are editing and the check below
          # makes in the sandbox. `-D warnings`, as Cargo.toml has clippy's lints at `warn`, so that
          # without it the run gates nothing.
          clippyRun = args: "--all-targets --workspace ${args} -- -D warnings";

          # `cargo fmt` exits 0 when rustfmt dies by a signal. A shell hands it the status as a number.
          rustfmt = pkgs.writeShellScript "rustfmt" ''
            ${toolchain}/bin/rustfmt "$@" || exit
          '';

          nixFiles = sourceOf [ (pkgs.lib.fileset.fileFilter (file: file.hasExt "nix") ./.) ];

          # On the nix files alone, so that editing any other file reruns neither linter.
          nixLint =
            tool: args:
            pkgs.runCommand "serialmint-${tool.pname}" { } ''
              cd ${nixFiles}
              ${pkgs.lib.getExe tool} ${args}
              touch "$out"
            '';

          dev = import ./nix/dev {
            inherit
              pkgs
              toolchain
              clippyRun
              rustfmt
              ;
          };
        in
        {
          inherit dev serialmint;

          checks = {
            inherit serialmint;

            # In the dev profile, as `dev clippy` runs, and on the dependencies the tests built. It
            # reads clippy.toml, which no build does, so editing that rebuilds no package.
            clippy = craneLib.cargoClippy (
              devProfile
              // {
                src = sourceOf (
                  cargoFiles
                  ++ [
                    ./tests
                    ./clippy.toml
                  ]
                );
                cargoClippyExtraArgs = clippyRun "";
                doInstallCargoArtifacts = false;
              }
            );

            # crane limits the threads through RUST_TEST_THREADS, which nextest does not read.
            test = craneLib.cargoNextest (
              devProfile
              // {
                src = sourceOf (
                  cargoFiles
                  ++ [
                    ./tests
                    ./.config/nextest.toml
                    # A test run builds the examples, so that `dev test` fails on one that does not
                    # compile.
                    (pkgs.lib.fileset.maybeMissing ./examples)
                  ]
                );
                cargoNextestExtraArgs = ''--profile ci --test-threads "$NIX_BUILD_CORES"'';
              }
            );

            # nextest runs no doctests.
            doctest = craneLib.cargoDocTest devProfile;

            # Each reads only the files it checks, so that editing any other reruns neither.
            fmtRust = craneLib.cargoFmt {
              src = sourceOf [
                ./src
                ./tests
                ./Cargo.toml
                ./rustfmt.toml
              ];
              cargoExtraArgs = "--all";
              RUSTFMT = rustfmt;
              doInstallCargoArtifacts = false;
            };

            fmtNix =
              pkgs.runCommand "serialmint-fmt-nix"
                {
                  nativeBuildInputs = [ pkgs.nixfmt ];
                  src = nixFiles;
                }
                ''
                  find "$src" -name '*.nix' -exec nixfmt --check {} +
                  touch "$out"
                '';

            # `--locked`, so that a stale lock fails and isn't checked as cargo would rewrite it.
            deny = craneLib.cargoDeny {
              src = sourceOf (cargoFiles ++ [ ./deny.toml ]);
              cargoDenyExtraArgs = "--offline --locked";
            };

            statix = nixLint pkgs.statix "check .";

            # --hidden, as it would skip a .nix in a hidden folder that `dev lint` reads.
            deadnix = nixLint pkgs.deadnix "--hidden --fail .";
          };

          # `nix fmt`, which `dev` refuses to run outside this repository.
          formatter = pkgs.writeShellApplication {
            name = "serialmint-fmt";
            text = ''
              exec ${pkgs.lib.getExe dev} fmt "$@"
            '';
          };

          shell = pkgs.mkShell {
            packages = [
              toolchain
              dev
            ];
          };
        };

      bySystem = nixpkgs.lib.genAttrs systems build;
    in
    {
      packages = nixpkgs.lib.mapAttrs (_: built: {
        inherit (built) dev serialmint;
        default = built.serialmint;
      }) bySystem;

      devShells = nixpkgs.lib.mapAttrs (_: built: { default = built.shell; }) bySystem;

      checks = nixpkgs.lib.mapAttrs (_: built: built.checks) bySystem;

      formatter = nixpkgs.lib.mapAttrs (_: built: built.formatter) bySystem;
    };
}
