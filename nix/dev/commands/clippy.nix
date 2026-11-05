{
  pkgs,
  buildTools,
  clippyRun,
  ...
}:
{
  name = "clippy";
  usage = "[args...]";
  help = "cargo clippy over every target, warnings denied";
  tools = buildTools ++ [ pkgs.git ];
  text = ''
    cargo clippy --locked ${clippyRun} "$@" -- -D warnings
  '';
}
