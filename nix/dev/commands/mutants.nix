{
  pkgs,
  buildTools,
  testTools,
  ...
}:
{
  name = "mutants";
  usage = "[args...]";
  help = "cargo mutants on nextest; --in-diff <file> takes only the lines of a diff";
  tools =
    buildTools
    ++ testTools
    ++ [
      pkgs.cargo-mutants
      pkgs.git
    ];
  text = ''
    cargo mutants "$@"
  '';
}
