# The licences nixpkgs cannot give tests/licenses.sh: derivations that the
# modules generate without a meta.license, and what a host gets from outside
# Nix, keyed by the name its install takes.
{ lib }:
with lib.licenses;
let
  # MoonBit's official installer, on personal-mac and wsl (ADR 0012): the compiler's
  # licence, then that of moon and core.
  moonbit = [
    {
      shortName = "moonbit-psl-1";
      fullName = "MoonBit Public Source License, Version 1";
      url = "https://www.moonbitlang.com/licenses/moonbit-public-source-license-v1";
      free = false;
      redistributable = true;
    }
    asl20
  ];
in
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
    personal-mac = { inherit moonbit; };
    work-mac = { };
    # MoonBit inside WSL; the Windows side, by winget id, and the font, installed by hand.
    wsl = {
      inherit moonbit;
      "StablyAI.Orca" = mit;
      "Microsoft.WindowsTerminal" = mit;
      "AgileBits.1Password" = unfree;
      "AgileBits.1Password.CLI" = unfree;
      raycast = unfree;
      udev-gothic-nf = ofl;
    };
  };
}
