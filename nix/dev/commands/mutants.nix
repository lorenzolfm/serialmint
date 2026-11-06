{ pkgs, toolchain, ... }:
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
    cargo mutants "$@"
  '';
}
