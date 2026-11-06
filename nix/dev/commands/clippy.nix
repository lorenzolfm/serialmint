{
  pkgs,
  toolchain,
  clippyRun,
  ...
}:
{
  name = "clippy";
  usage = "[args...]";
  help = "cargo clippy over every target, warnings denied";
  tools = [
    toolchain
    pkgs.stdenv.cc
  ];
  text = ''
    cargo clippy --locked ${clippyRun ''"$@"''}
  '';
}
