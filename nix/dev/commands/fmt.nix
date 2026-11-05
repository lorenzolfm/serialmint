{ pkgs, toolchain, ... }:
let
  # `cargo fmt` exits 0 when rustfmt dies by a signal. A shell hands it the status as a number.
  rustfmt = pkgs.writeShellScript "rustfmt" ''
    ${toolchain}/bin/rustfmt "$@" || exit
  '';
in
{
  name = "fmt";
  usage = "[--check]";
  help = "format the rust and nix files; --check only says what would change";
  tools = [
    toolchain
    pkgs.diffutils
    pkgs.findutils
    pkgs.git
    pkgs.nixfmt
  ];
  text = ''
    case "$#:$*" in
      0:)
        rust=()
        nix=()
        ;;
      1:--check)
        rust=(--check)
        nix=(--check)
        ;;
      *)
        echo "usage: dev fmt [--check]" >&2
        exit 2
        ;;
    esac

    RUSTFMT=${rustfmt} cargo fmt --all "''${rust[@]}"
    git ls-files -z --cached --others --exclude-standard '*.nix' | xargs -0 nixfmt "''${nix[@]}"
  '';
}
