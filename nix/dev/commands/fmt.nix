{
  pkgs,
  toolchain,
  rustfmt,
  ...
}:
{
  name = "fmt";
  usage = "[--check]";
  help = "format the rust and nix files; --check only says what would change";
  tools = [
    toolchain
    pkgs.findutils
    pkgs.git
    pkgs.nixfmt
  ];
  text = ''
    # Anything else is refused, as a mistyped --check must not write the whole tree.
    case "$#:$*" in
      0:)
        flags=()
        ;;
      1:--check)
        flags=(--check)
        ;;
      *)
        echo "usage: dev fmt [--check]" >&2
        exit 2
        ;;
    esac

    RUSTFMT=${rustfmt} cargo fmt --all "''${flags[@]}"

    # Untracked files count, as cargo fmt reaches an untracked module too. Ignored ones don't.
    git ls-files -z --cached --others --exclude-standard '*.nix' | xargs -0 nixfmt "''${flags[@]}"
  '';
}
