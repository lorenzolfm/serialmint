{
  pkgs,
  toolchain,
  buildTools,
  clippyRun,
  testRun,
  nextestRun,
  testTools,
}:
let
  inherit (pkgs) lib;

  records = map (
    file:
    import (./commands + "/${file}") {
      inherit
        pkgs
        toolchain
        buildTools
        clippyRun
        testRun
        nextestRun
        testTools
        ;
    }
  ) (builtins.attrNames (builtins.readDir ./commands));

  program =
    record:
    lib.getExe (
      pkgs.writeShellApplication {
        name = "dev-${record.name}";
        runtimeInputs = record.tools;
        inheritPath = false;
        inherit (record) text;
      }
    );

  signature = record: "dev ${record.name} ${record.usage}";
  width = lib.foldl' lib.max 0 (map (record: lib.stringLength (signature record)) records);

  helpLines = lib.concatMapStringsSep "\n" (
    record:
    "printf '  %s%-${toString width}s%s  %s\\n' \"$cyan\" ${lib.escapeShellArg (signature record)} \"$reset\" ${lib.escapeShellArg record.help}"
  ) records;

  dispatch = lib.concatMapStringsSep "\n" (record: ''
    ${record.name})
      enter_checkout
      exec ${program record} "$@"
      ;;
  '') records;
in
pkgs.writeShellApplication {
  name = "dev";
  meta.description = "serialmint build recipes on the flake-pinned toolchain";
  text = ''
    paint() {
      if [ -t "$1" ] && [ -z "''${NO_COLOR:-}" ]; then
        bold=$'\033[1m'
        cyan=$'\033[36m'
        red=$'\033[1;31m'
        reset=$'\033[0m'
      else
        bold=""
        cyan=""
        red=""
        reset=""
      fi
    }

    usage() {
      paint "$1"
      printf '%s%s%s\n\n' "$bold" 'dev: serialmint build recipes (pinned nix tooling)' "$reset"
      ${helpLines}
    }

    error() {
      paint 2
      printf '%sdev:%s %s\n' "$red" "$reset" "$1" >&2
    }

    # A command can write tracked files, so it runs only in a checkout of this repository.
    enter_checkout() {
      root="$(${lib.getExe pkgs.git} rev-parse --show-toplevel 2>/dev/null)" || root=""
      if ! ${lib.getExe pkgs.gnugrep} --quiet --line-regexp 'name = "serialmint"' "$root/Cargo.toml" 2>/dev/null; then
        error "run this inside the serialmint checkout"
        exit 2
      fi
      cd "$root"
    }

    cmd="''${1:-help}"
    shift || true

    case "$cmd" in
      help | -h | --help)
        usage 1
        ;;
      ${dispatch}
      *)
        error "unknown command $cmd"
        printf '\n' >&2
        usage 2 >&2
        exit 2
        ;;
    esac
  '';
}
