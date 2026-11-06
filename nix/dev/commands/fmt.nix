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

    # Not `cargo fmt`: cargo looks in $CARGO_HOME/bin before PATH, so it could run another
    # cargo-fmt, which under rustup is a proxy that can install a toolchain. CARGO is what cargo
    # would have set.
    #
    # No --all, as that also writes local path dependencies, which can be outside this repository.
    # From the root, this reaches every workspace member without it.
    CARGO="$(command -v cargo)" RUSTFMT=${rustfmt} cargo-fmt "''${flags[@]}"

    # Untracked files count, as cargo-fmt reaches an untracked module too. Ignored ones don't.
    git ls-files -z --cached --others --exclude-standard '*.nix' | xargs -0 nixfmt "''${flags[@]}"
  '';
}
