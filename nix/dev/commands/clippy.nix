{
  pkgs,
  toolchain,
  clippyRun,
  ...
}:
{
  name = "clippy";
  usage = "[cargo args...]";
  help = "cargo clippy over every target, warnings denied";
  tools = [
    toolchain
    pkgs.stdenv.cc
  ];
  text = ''
    # Not `cargo clippy`: cargo looks in $CARGO_HOME/bin before PATH, so it could run another
    # clippy, which under rustup is a proxy that can install a toolchain. CARGO is what cargo would
    # have set.
    CARGO="$(command -v cargo)" cargo-clippy clippy --locked ${clippyRun ''"$@"''}
  '';
}
