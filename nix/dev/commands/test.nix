{ pkgs, toolchain, ... }:
{
  name = "test";
  usage = "[args...]";
  help = "the tests on nextest, then the doctests, which nextest does not run";
  tools = [
    toolchain
    pkgs.cargo-nextest
    pkgs.stdenv.cc
  ];
  text = ''
    # With no TERM, on a terminal, nextest prints no test and no summary.
    case "''${TERM:-dumb}" in
      dumb) export NEXTEST_SHOW_PROGRESS="''${NEXTEST_SHOW_PROGRESS:-counter}" ;;
    esac

    cargo nextest run --locked "$@"
    cargo test --doc --locked
  '';
}
