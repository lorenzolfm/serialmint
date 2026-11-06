{ pkgs, toolchain, ... }:
{
  name = "deny";
  usage = "[check...]";
  help = "cargo deny over Cargo.lock: advisories, bans, licenses and sources";
  tools = [
    toolchain
    pkgs.cargo-deny
    # `advisories` fetches its database with it.
    pkgs.git
  ];
  text = ''
    cargo deny --locked check "$@"
  '';
}
