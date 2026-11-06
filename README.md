# Serialmint

> Gimme strict serializability or gimme death

![Give me strict serializability or give me death](assets/banner.png)

A highly opinionated Cashu mint implementation built with PostgreSQL, Rust and Paranoia

Work in progress: the binary only says hello.

## Develop

```sh
nix develop    # or: direnv allow, once
dev help       # the command set
```

Run cargo only inside that shell. It has the nightly that `rust-toolchain.toml` pins, and
`.cargo/config.toml` holds flags that a stable cargo refuses.

`dev` holds the recipes, and works from anywhere in a checkout. Each command brings the pinned tools
it runs on, so it also works outside the shell, as `nix run .#dev -- clippy`.

| Command | What it is for |
|---|---|
| `dev fmt` | Format the rust and nix files. `--check` only says what would change |
| `dev lint` | statix and deadnix over the nix files |
| `dev check` | Whether every target compiles |
| `dev clippy` | The lints over every target, warnings denied. A plain `cargo clippy` passes what this fails |
| `dev test` | The tests on nextest, then the doctests |
| `dev mutants` | Whether the tests notice a broken line. `--in-diff <file>` takes only the lines of a diff. Doctests don't count, and nothing inside an `assert!` gets mutated |
| `dev deny` | `Cargo.lock`'s crates against RustSec's advisories, and their bans, licenses and sources. `dev deny advisories` runs one of the four |
| `dev clean` | `cargo clean` |

Before a commit, run `dev fmt`, `dev lint`, `dev clippy` and `dev test`, and `dev deny` when
`Cargo.lock` changes.

`nix build` builds the binary at `./result/bin/serialmint`, and runs no tests. `nix flake check` runs
them in the sandbox, with clippy, the formatters, the nix lints and `dev deny`'s three offline checks.

A flake sees only the files git knows of, so `git add` a new file before you trust either of those.
With a failing test left untracked, `dev test` fails and `nix flake check` passes. A new command in
`nix/dev/commands/` appears in `dev` only after its `git add`, and under direnv after `direnv reload`
too.

## License

[MIT](LICENSE).
