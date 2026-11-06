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
        "aarch64-darwin"
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

          serialmint = craneLib.buildPackage {
            src = craneLib.cleanCargoSource ./.;
            strictDeps = true;
          };

          dev = import ./nix/dev { inherit pkgs toolchain; };
        in
        {
          inherit dev serialmint;

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
    };
}
