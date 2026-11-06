{ pkgs, toolchain }:
let
  inherit (pkgs) lib;

  # One file for each command in ./commands, so that adding a command touches nothing here.
  records = map (file: import (./commands + "/${file}") { inherit pkgs toolchain; }) (
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

  helpLines = lib.concatMapStringsSep "\n" (
    record: "echo ${lib.escapeShellArg "  dev ${record.name} ${record.usage}  ${record.help}"}"
  ) records;

  dispatch = lib.concatMapStringsSep "\n" (record: ''
    ${record.name})
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
