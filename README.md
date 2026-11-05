# serialmint

A Cashu mint on Postgres SERIALIZABLE. Work in progress: the binary does nothing yet.

## Develop

```sh
nix develop    # or: direnv allow, once
dev help       # the command set
```

`dev` runs each recipe on the tools that the flake pins, so it also works outside the devshell, as
`nix run .#dev -- clippy`.

`nix build` builds the binary at `./result/bin/serialmint`, and it runs the tests in the sandbox on the
way. `nix flake check` also runs clippy and the formatters. CI runs these, `dev deny`, and `dev mutants`
on the lines that each pull request changes.
