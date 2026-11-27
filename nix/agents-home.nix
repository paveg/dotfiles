# ~/.claude and ~/.codex wiring (docs/design.md "Agent configuration").
# managedSettings is the macOS drop-in's path, or null where there is none (wsl).
# linkHome links a path under home/ from the checkout (nix/home.nix).
{ lib, pkgs, config, host, managedSettings, linkHome, ... }:
let
  agents = import ./agents.nix { inherit pkgs; };
  claudeSource = ../home/.claude;

  # Only what the repository holds is linked, one entry at a time, never the
  # whole of ~/.claude, which also holds Claude Code's runtime state.
  entries = lib.filter (entry: builtins.pathExists (claudeSource + "/${entry}")) [
    "CLAUDE.md"
    "rules"
    "agents"
    "references"
    "statusline.sh"
  ];

  skillsOf =
    profile:
    let
      dir = claudeSource + "/skills/${profile}";
    in
    lib.optionals (builtins.pathExists dir) (
      lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir))
    );
  skills = lib.genAttrs (skillsOf "common") (_: "common") // lib.genAttrs (skillsOf host.profile) (_: host.profile);
  clashes = lib.intersectLists (skillsOf "common") (skillsOf host.profile);
in
{
  home.file =
    lib.throwIf (clashes != [ ])
      "home/.claude/skills: ${lib.concatStringsSep ", " clashes} is in both common and ${host.profile}"
      (
        lib.listToAttrs (map (entry: lib.nameValuePair ".claude/${entry}" { source = linkHome ".claude/${entry}"; }) entries)
        # Codex reads its global instructions only from its own home.
        // lib.optionalAttrs (lib.elem "CLAUDE.md" entries) { ".codex/AGENTS.md".source = linkHome ".claude/CLAUDE.md"; }
        // lib.mapAttrs' (
          name: profile: lib.nameValuePair ".claude/skills/${name}" { source = linkHome ".claude/skills/${profile}/${name}"; }
        ) skills
      );

  # A regular file, not a home.file link: Claude Code and Orca write to it.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe agents.claude-settings} settings ${host.profile} ${lib.escapeShellArg config.home.homeDirectory}${
      lib.optionalString (managedSettings != null) " ${lib.escapeShellArg managedSettings}"
    }
  '';
}
