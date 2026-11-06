# serialmint

Run cargo inside `nix develop`, on the pinned nightly. `.cargo/config.toml` holds flags that a stable cargo refuses.

`dev` comes with that shell, and `nix run .#dev -- <command>` runs it outside. `dev help` lists every command.

Before a commit, run `dev fmt`, `dev lint`, `dev clippy` and `dev test`, and `dev deny` when `Cargo.lock` changes. `dev clippy` is the lint gate: clippy's lints are at `warn`, so a plain `cargo clippy` passes what it fails.

A flake sees only the files git knows of, so `git add` a new file before you trust `nix build` or `nix flake check`. With a failing test left untracked, `dev test` fails and the flake's `test` check passes. A new command in `nix/dev/commands/` appears in `dev` only after its `git add`.
