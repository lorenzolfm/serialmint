{
  pkgs,
  buildTools,
  testRun,
  nextestRun,
  testTools,
  ...
}:
{
  name = "test";
  usage = "[args...]";
  help = "the tests on nextest, then the doctests";
  tools = buildTools ++ testTools ++ [ pkgs.git ];
  text = ''
    case "''${TERM:-dumb}" in
      dumb) export NEXTEST_SHOW_PROGRESS="''${NEXTEST_SHOW_PROGRESS:-counter}" ;;
    esac
    cargo nextest run --locked ${nextestRun} "$@"
    cargo test --doc --locked ${testRun}
  '';
}
