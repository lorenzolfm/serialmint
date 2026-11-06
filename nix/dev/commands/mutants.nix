{ pkgs, toolchain, ... }:
let
  # What cargo-mutants runs as cargo. It runs `cargo nextest` itself, and cargo looks in
  # $CARGO_HOME/bin before PATH, so it could run another nextest than `dev test` does. CARGO is what
  # cargo would have set.
  cargo = pkgs.writeShellScript "cargo" ''
    if [ "$1" = nextest ]; then
      shift
      CARGO="$(command -v cargo)" exec cargo-nextest nextest "$@"
    fi
    exec cargo "$@"
  '';
in
{
  name = "mutants";
  usage = "[args...]";
  help = "cargo mutants on nextest; --in-diff <file> takes only the lines of a diff";
  tools = [
    toolchain
    pkgs.cargo-mutants
    pkgs.cargo-nextest
    pkgs.stdenv.cc
  ];
  text = ''
    # Not `cargo mutants`, for the same reason. cargo-mutants finds its cargo through CARGO.
    CARGO=${cargo} cargo-mutants mutants "$@"
  '';
}
