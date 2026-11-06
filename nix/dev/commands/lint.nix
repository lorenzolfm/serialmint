{ pkgs, ... }:
{
  name = "lint";
  usage = "";
  help = "statix and deadnix over the nix files";
  tools = [
    pkgs.deadnix
    pkgs.findutils
    pkgs.git
    pkgs.statix
  ];
  text = ''
    # Both run even when one fails, so that a finding of one doesn't hide a finding of the other.
    status=0

    # deadnix exits 0 on a syntax error, and only statix fails on one.
    statix check . || status=1

    # git's list, as deadnix walks into target/, where statix reads .gitignore.
    git ls-files -z --cached --others --exclude-standard '*.nix' |
      xargs -0 deadnix --fail || status=1

    exit "$status"
  '';
}
