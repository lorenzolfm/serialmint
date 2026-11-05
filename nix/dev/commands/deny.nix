{ pkgs, toolchain, ... }:
{
  name = "deny";
  usage = "";
  help = "check Cargo.lock against RustSec's advisories, the banned crates and the allowed sources";
  tools = [
    toolchain
    pkgs.cargo-deny
    pkgs.git
  ];
  text = ''
    cargo deny check advisories bans sources
  '';
}
