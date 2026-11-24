# ADR 0007: Agent guardrails in three layers, hooks built with writeShellApplication

- Status: Accepted (sandbox adoption gated on measurement)
- Date: 2026-11-25

## Context

The previous setup guarded agents with seven Claude Code hooks: six bash scripts depending on `jq` and one Python script. Two findings changed how guards should be built:

- Claude Code's docs state that Bash permission patterns are not a security boundary (`bash -c '…'` is not unwrapped), and that a PreToolUse hook that exits with anything other than 0 or 2, cannot start, times out, or prints invalid JSON lets the tool call proceed, unless the hook sets `onFailure: "block"`.
- Measured: with `jq` unresolvable on PATH, the credential guard exited 0 with no output (the call is allowed), and the database guard exited 127 (the call proceeds). Hooks run with Claude Code's environment, and a GUI-launched app may start with launchd's default PATH.

## Decision

Guard in three layers, each doing what it can enforce:

| Layer | Covers | Strength |
|---|---|---|
| Sandbox (`sandbox.enabled`, `filesystem.denyRead`, network allowlist, `allowUnsandboxedCommands: false`) | Reads, writes, and network of Bash commands | Enforced, but Bash only |
| `permissions.deny` (e.g. `Read(~/.aws/**)`) | Claude's file tools, and common Bash forms (`cat`, `head`, `sed`, redirections) | Reliable for file tools; Bash can be bypassed |
| Hooks | Judgements the two layers cannot express | A tripwire against mistakes, not a defence against a hostile agent |

Triage of the previous hooks:

| Hook | Outcome |
|---|---|
| Credential-read guard | Removed. Replaced by `Read(...)` deny rules and sandbox `denyRead` |
| Unsigned-commit guard | Removed. Replaced by a `permissions.deny` rule for `--no-gpg-sign` and a "require signed commits" rule on GitHub |
| Destructive-database guard | Kept as a hook, with `onFailure: "block"` |
| Comment-rot guard | Kept as a hook (its value is feedback at write time), rewritten from Python |
| PR, browser, and Japanese-writing context injectors | Kept as hooks; they fail open |

Every remaining hook is built with Nix's `writeShellApplication`:

- Dependencies (`jq`, coreutils, grep) are pinned through `runtimeInputs`, so nothing is resolved from the caller's PATH.
- shellcheck runs at build time.
- `settings.json` refers to each hook by its store path, written by the generator in ADR 0003.
- Guards set `onFailure: "block"` and also return `deny` on malformed input. Injectors fail open.
- Each guard has a test that is shown to fail when the guard is deliberately broken.

## Consequences

- A missing or broken dependency can no longer turn a guard into an allow.
- `python3` is no longer needed globally.
- The same build works on macOS and WSL2. Codex's hook contract has not been checked, so this does not claim to cover Codex.
- Regular-expression matching in shell still has blind spots (for example `bash -c` wrapping). If closing them becomes necessary, move the database guard to a Go binary built with `buildGoModule` that parses commands into a syntax tree (`mvdan.cc/sh`).
- The sandbox is not yet enabled. The 1Password SSH agent socket, the ghtkn agent, the Nix daemon socket, and `op` / `ksm` network calls cross its boundary, and the macOS default for `allowUnixSockets` is not documented. Enable it only after measuring these on each host.
- The agent can still edit its own guards: hook sources are symlinks into this repository, and `settings.json` is a regular file. `Edit` deny rules on `~/.claude/hooks/**` and `~/.claude/settings.json` prevent accidents, not intent.

## Alternatives considered

- **Keep bash scripts that resolve `jq` from PATH (status quo)**: guards fail open when PATH is short. Rejected.
- **Go binary for every hook now**: stronger parsing, but adds a toolchain before there is a concrete bypass to close. Deferred to the upgrade condition above.
- **Python or Deno**: needs a language runtime installed globally, and the repository owner prefers not to write Python. Rejected.
- **Rely on hooks for credential protection**: hooks and Bash patterns are not a boundary, and file tools are better covered by `Read` deny rules. Rejected.
