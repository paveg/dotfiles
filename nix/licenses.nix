# The licences nixpkgs cannot give tests/licenses.sh: derivations that the
# modules generate without a meta.license, and what a host gets from outside
# Nix, keyed by the name its install takes.
{ lib }:
with lib.licenses;
{
  generated = {
    # home-manager's own, under its MIT licence.
    "home-configuration-reference-manpage" = mit;
    "hm-session-vars.sh" = mit;
    "dummy-xdg-mime-dirs1" = mit;
    "dummy-xdg-mime-dirs2" = mit;
    # nix-darwin's own, under its MIT licence.
    "darwin-help" = mit;
    "darwin-manpages" = mit;
    "darwin-manual-html" = mit;
    "darwin-option" = mit;
    "darwin-rebuild" = mit;
    "darwin-uninstaller" = mit;
    "darwin-version" = mit;
  };

  outsideNix = {
    personal-mac = { };
    work-mac = { };
    # The Windows side, by winget id, and the font, installed by hand.
    wsl = {
      "StablyAI.Orca" = mit;
      "Microsoft.WindowsTerminal" = mit;
      "AgileBits.1Password" = unfree;
      "AgileBits.1Password.CLI" = unfree;
      raycast = unfree;
      udev-gothic-nf = ofl;
    };
  };
}
