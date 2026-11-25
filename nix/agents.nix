# Hook builds for the coding agents (docs/adr/0007-agent-guardrails.md). Nothing
# installs or registers these yet; the generated settings.json will refer to
# them by store path.
{ pkgs }:
let
  hookDir = ../home/.claude/hooks;

  # inheritPath = false keeps the caller's PATH out of the script, so a hook
  # cannot fail open because jq was unresolvable where Claude Code was started.
  # runtimeInputs is what the guards actually call. shellcheck runs in the
  # build, over the engine and the guard together.
  guard =
    name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.jq
        pkgs.coreutils
        pkgs.gnugrep
      ];
      inheritPath = false;
      text = builtins.readFile "${hookDir}/lib/guard.sh" + builtins.readFile "${hookDir}/${name}.sh";
      meta.description = "PreToolUse guard hook for Claude Code: ${name}";
    };
in
{
  block-destructive-db = guard "block-destructive-db";
  block-sensitive-read = guard "block-sensitive-read";
}
