# Hook builds for the coding agents (docs/adr/0007-agent-guardrails.md), and
# the generator of settings.json, which refers to them by store path.
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
      text = builtins.readFile "${hookDir}/lib/guard.sh" + builtins.readFile "${hookDir}/${name}.sh" + "\nguard_main\n";
      meta.description = "PreToolUse guard hook for Claude Code: ${name}";
    };
  block-destructive-db = guard "block-destructive-db";
  block-sensitive-read = guard "block-sensitive-read";

  # A checker, not a guard: it fails open, so it gets no engine and no EXIT trap.
  check-reply-language = pkgs.writeShellApplication {
    name = "check-reply-language";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    inheritPath = false;
    text = builtins.readFile "${hookDir}/check-reply-language.sh";
    meta.description = "Stop hook for Claude Code: sends an English reply to a Japanese message back";
  };

  guardHook = pkg: {
    type = "command";
    command = pkgs.lib.getExe pkg;
    onFailure = "block";
  };
  # The guards alone go to the macOS drop-in too; the checker stays out of
  # managed scope, where a user could not turn a broken one off.
  guardHooks.hooks.PreToolUse = [
    {
      matcher = "Bash";
      hooks = map guardHook [
        block-destructive-db
        block-sensitive-read
      ];
    }
  ];
  settingsHooks.hooks = guardHooks.hooks // {
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = pkgs.lib.getExe check-reply-language;
          }
        ];
      }
    ];
  };

  claude-settings = pkgs.writeShellApplication {
    name = "claude-settings";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    inheritPath = false;
    text = ''
      common_json=${../home/.claude/settings.common.json}
      personal_json=${../home/.claude/settings.personal.json}
      hooks_json=${pkgs.writeText "claude-hooks.json" (builtins.toJSON settingsHooks)}
      guard_hooks_json=${pkgs.writeText "claude-guard-hooks.json" (builtins.toJSON guardHooks)}
      # Orca's entries as Orca writes them, kept here rather than carried over
      # from the file being replaced (ADR 0003).
      orca_json=${./orca-hooks.json}
    ''
    + builtins.readFile ./claude-settings.sh;
    meta.description = "Writes ~/.claude/settings.json from the common and profile settings";
  };
in
{
  inherit
    block-destructive-db
    block-sensitive-read
    check-reply-language
    claude-settings
    ;
}
