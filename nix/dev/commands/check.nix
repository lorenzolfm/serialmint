{ pkgs, toolchain }:
{
  name = "check";
  usage = "[args...]";
  help = "cargo check over every target";
  tools = [
    toolchain
    pkgs.stdenv.cc
  ];
  text = ''
    cargo check --locked --all-targets --workspace "$@"
  '';
}
