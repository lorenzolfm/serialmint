args@{ pkgs, ... }:
let
  inherit (pkgs) lib;

  # One file for each command in ./commands, so that adding a command touches nothing here.
  records = map (file: import (./commands + "/${file}") args) (
    builtins.attrNames (builtins.readDir ./commands)
  );

  # inheritPath = false, so that a command runs only on the tools its record names.
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
    "printf '  %-${toString width}s  %s\\n' ${lib.escapeShellArg (signature record)} ${lib.escapeShellArg record.help}"
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
    usage() {
      echo 'dev: serialmint build recipes (pinned nix tooling)'
      echo
      ${helpLines}
    }

    # A command can write tracked files, so it runs only in this repository, from its root. The root's
    # Cargo.toml says which repository it is, and no git at all fails the same way.
    enter_checkout() {
      root="$(${lib.getExe pkgs.git} rev-parse --show-toplevel 2>/dev/null)" || root=""
      if ! ${lib.getExe pkgs.gnugrep} --quiet --line-regexp 'name = "serialmint"' "$root/Cargo.toml" 2>/dev/null; then
        echo 'dev: run this inside the serialmint checkout' >&2
        exit 2
      fi
      cd "$root"
    }

    cmd="''${1:-help}"
    shift || true

    case "$cmd" in
      help | -h | --help)
        usage
        ;;
      ${dispatch}
      *)
        printf 'dev: unknown command %s\n\n' "$cmd" >&2
        usage >&2
        exit 2
        ;;
    esac
  '';
}
