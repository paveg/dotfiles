# The gh wrapper (docs/adr/0004-github-auth-ghtkn.md), built here so that CI
# tests the same derivation the profile installs.
{ pkgs }:
let
  # No runtimeInputs: ghtkn, and whatever gh itself runs, come from the
  # caller's PATH, so nothing is put in front of it.
  wrapper = pkgs.writeShellApplication {
    name = "gh";
    text = ''
      gh=${pkgs.lib.getExe pkgs.gh}
    ''
    + builtins.readFile ./gh.sh;
  };
in
{
  # The wrapper with gh's name, licence and zsh completion. The real gh stays
  # out of home.packages, where the two would collide.
  gh =
    pkgs.runCommand "gh-${pkgs.gh.version}"
      {
        meta = {
          inherit (pkgs.gh.meta) license;
          mainProgram = "gh";
        };
      }
      ''
        mkdir -p $out/bin $out/share/zsh/site-functions
        ln -s ${pkgs.lib.getExe wrapper} $out/bin/gh
        ln -s ${pkgs.gh}/share/zsh/site-functions/_gh $out/share/zsh/site-functions/_gh
      '';
}
