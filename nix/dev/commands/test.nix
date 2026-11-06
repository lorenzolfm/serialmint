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

    # Not `cargo nextest`: cargo looks in $CARGO_HOME/bin before PATH, so it could run another
    # nextest. CARGO is what cargo would have set, for a test that reads it.
    CARGO="$(command -v cargo)" cargo-nextest nextest run --locked "$@"
    cargo test --doc --locked
  '';
}
