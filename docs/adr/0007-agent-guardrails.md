# ADR 0007: Agent guardrails in three layers, hooks built with writeShellApplication

- Status: Accepted (sandbox adoption gated on measurement)
- Date: 2026-11-25

## Context

The previous setup registered eight hooks of its own: six bash scripts that use `jq` (`block-credential-read`, `block-destructive-db`, `block-unsigned-commits`, `gh-pr-inject`, `browser-inject`, `japanese-writing-inject`), one Python script (`block-rot-comments`), and one `type: "agent"` Stop hook that checks for unaddressed requests. Two other tools write hook entries into the same `settings.json`: herdr installs and manages `herdr-agent-state.sh`, and Orca merges 16 entries that report agent status to Orca and let it answer permission requests. Two findings changed how guards should be built:

- Claude Code's docs state that Bash permission patterns are not a security boundary (`bash -c '…'` is not unwrapped), and that a PreToolUse hook that exits with anything other than 0 or 2, cannot start, times out, or prints invalid output lets the tool call proceed, unless the hook sets `onFailure: "block"` (v2.1.295 or later). Plain stdout with exit 0 is not a failure, so `onFailure` does not catch a guard that silently exits 0.
- Measured: with `jq` unresolvable on PATH, the credential guard exited 0 with no output (the call proceeds unguarded), and the database guard exited 127 (the call proceeds). Hooks run with Claude Code's environment, and a GUI-launched app may start with launchd's default PATH.

## Decision

Guard in three layers, each doing what it can enforce:

| Layer | Covers | Strength |
|---|---|---|
| Sandbox (`sandbox.enabled`, `filesystem.denyRead`, network allowlist, `allowUnsandboxedCommands: false`) | Reads, writes, and network of Bash commands | Enforced, but Bash only |
| `permissions.deny` (e.g. `Read(~/.aws/**)`) | Claude's file tools, and common Bash forms (`cat`, `head`, `sed`, redirections) | Reliable for file tools; Bash can be bypassed |
| Hooks | Judgements the two layers cannot express | A tripwire against mistakes, not a defence against a hostile agent |

Hooks are classed by what their own failure should do. A guard protects data or credentials and fails closed. A checker enforces a quality rule: it denies on a match but fails open, because a bug in a style check must not halt an unattended agent loop. An injector adds context and fails open.

Triage of the previous hooks:

| Hook | Kind | Outcome |
|---|---|---|
| Destructive-database guard | Guard | Kept, with `onFailure: "block"` |
| Credential-read guard | Guard | Kept until sandbox `denyRead` is enabled and measured on the host, then removed. Until then `Read(...)` deny rules miss Bash reads they do not recognize |
| Unsigned-commit guard | — | Removed. Replaced by deny rules for `--no-gpg-sign`, `-c commit.gpgsign=false`, and `git config … commit.gpgsign`, and by "require signed commits" on GitHub |
| Comment-rot check | Checker | Kept (its value is feedback at write time), rewritten from Python; fails open |
| PR, browser, and Japanese-writing context | Injector | Kept |
| Unaddressed-request check (`type: "agent"`) | Checker | Kept as a prompt in the common settings; nothing to build |
| Orca entries | — | Not owned here. The settings generator writes them itself (ADR 0003) |
| herdr entry | — | Not owned here. The settings generator carries it over from the current file (ADR 0003), only if herdr is adopted |

Every remaining script hook is built with Nix's `writeShellApplication`:

- Dependencies (`jq`, coreutils, grep) are pinned through `runtimeInputs`, and `inheritPath = false` stops the default from appending the caller's PATH, so nothing is resolved from it.
- shellcheck runs at build time, and `errexit` / `nounset` / `pipefail` are on by default.
- `settings.json` refers to each hook by its store path, written by the generator in ADR 0003.
- On macOS the guards and `permissions.deny` are written twice: into a root-owned managed-settings drop-in, `managed-settings.d/50-dotfiles.json`, which no other tool is assumed to write, and then into `settings.json`. Claude Code merges hooks and lists across settings levels, and when the same handler is in both files it runs it once. `wsl` has no drop-in.
- Guards set `onFailure: "block"`, print `deny` on a match and nothing otherwise (never `allow`, which would skip the permission prompt), set `shopt -s inherit_errexit`, treat a matcher's error exit code as a failure rather than as "no match", and return `deny` on malformed input.
- A guard also traps `EXIT` and prints a fixed `deny` there, without jq, unless it reached its decision. An abort then leaves a deny decision and exit 0 rather than a non-zero exit that only `onFailure` would catch.
- Two kinds of rule, from one list of names per guard. Exact patterns read the command as written. One whole-command rule then asks whether it can be read at all: a command that names something the guard protects and uses an expansion (`$`, a backtick, `*`, `?`, `[`, `{`) anywhere is denied, because only a shell could work out what it reaches. Guards do not try to expand a command themselves; the measured cost of the rule is in [`verification.md`](../verification.md). Checkers and injectors keep the default `onFailure: "continue"`.
- Each guard has a test that is shown to fail when the guard is deliberately broken.

## Consequences

- A missing dependency can no longer let a call through: it is pinned. A guard that aborts is blocked by `onFailure`. Not every internal error aborts: `errexit` is suspended inside conditions and inside `$(…)` without `inherit_errexit` (measured on bash 3.2 and 5.3), and a matcher that errors inside `if grep …` reads as "no match" (measured), letting the call through to the normal permission flow. Guards narrow this with `inherit_errexit` and explicit matcher exit codes. The gap that remains is accepted for a tripwire and is part of the upgrade condition below.
- `python3` is no longer needed globally.
- The same build works on macOS and WSL2. Codex's hook contract has not been checked, so this does not claim to cover Codex.
- Regular-expression matching in shell still has blind spots (for example `bash -c` wrapping). If closing them becomes necessary, move the database guard to a Go binary built with `buildGoModule` that parses commands into a syntax tree (`mvdan.cc/sh`).
- Because a guard matches text rather than expanding it, these classes stay open, and stay acceptable for a tripwire: a command built at run time (`bash -c`, a variable holding the whole command); a script that opens a protected file without naming it; an encoded or symlinked path; and a glob that names neither a protected directory nor the segment that would (`ls ~/.config/*`), where denying would also deny `ls dir/*`.
- The sandbox is not yet enabled. The 1Password SSH agent socket, the ghtkn agent, the Nix daemon socket, and `op` / `ksm` network calls cross its boundary. On macOS an unset `allowUnixSockets` blocks every Unix socket, so each must be listed; on Linux and WSL2 only the all-or-nothing `allowAllUnixSockets` applies. `failIfUnavailable: true` is needed, or Claude Code silently runs unsandboxed when the sandbox cannot start. Enable it only after measuring these on each host.
- A running guard is a store path, so an edit to its source takes effect only at the next switch, which a human runs. `settings.json` is a regular file the agent could edit to repoint a hook; an `Edit` deny rule on it prevents accidents, not intent.
- A stale write by Orca or Claude Code can drop the guards from `settings.json`; the managed copy keeps them in effect (`spec/settings_writers.tla`). The managed copy is ignored when a higher managed source exists (server-managed settings or an MDM profile, possible on `work-mac`). On `wsl` the guards live only in `settings.json`: Claude Code's docs call `/etc/claude-code` user-writable there, so a drop-in would not keep the agent out.

## Alternatives considered

- **Keep bash scripts that resolve `jq` from PATH (status quo)**: guards fail open when PATH is short. Rejected.
- **Go binary for every hook now**: stronger parsing, but adds a toolchain before there is a concrete bypass to close. Deferred to the upgrade condition above.
- **Python or Deno**: needs a language runtime installed globally, and the repository owner prefers not to write Python. Rejected.
- **Rely on hooks for credential protection**: hooks and Bash patterns are not a boundary, and file tools are better covered by `Read` deny rules. Rejected.
