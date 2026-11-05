# serialmint

A Cashu mint on Postgres SERIALIZABLE. Work in progress: the binary does nothing yet.

## Build

Nix builds everything. `flake.lock` pins nixpkgs and the other inputs, and `rust-toolchain.toml` pins
the compiler.

```sh
nix build          # the binary, at ./result/bin/serialmint
nix flake check    # every CI gate: build, clippy, tests, rustfmt, cargo-deny
nix develop        # a shell with the pinned toolchain (direnv: `direnv allow`)
```

## Dependencies

`nix build .#serialmint-deny` runs `cargo deny check bans sources`. It refuses each crate of CDK, each
unknown registry and each git source that has no line in `deny.toml`.

## Mutants

CI runs `cargo mutants` on the lines that each pull request changes. A missed mutant fails the job.
Then add a test, or add a class to `exclude_re` in `.cargo/mutants.toml`, with its reason. To run the
same check here:

```sh
git diff origin/main... > /tmp/serialmint.diff
nix develop -c cargo mutants --in-diff /tmp/serialmint.diff
```

## Reproducibility

```sh
nix build .#serialmint .#serialmint.cargoArtifacts              # the package and its dependencies
nix build --rebuild .#serialmint .#serialmint.cargoArtifacts    # builds both again, and fails if the bytes differ
```

`--rebuild` compares with an earlier build, so run the first command once. CI runs this check on every
pull request.
