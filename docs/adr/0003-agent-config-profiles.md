# ADR 0003: Agent configuration wiring and per-profile skills and plugins

- Status: Accepted
- Date: 2026-11-25

## Context

`~/.claude` mixes files we author (instructions, rules, hooks, skills) with runtime state that Claude Code writes (`projects/`, `history.jsonl`, `sessions/`, `plugins/`, `.credentials.json`, and more). Work and personal machines need different skills, plugins, marketplaces, environment variables, and MCP servers, and the work side includes company information that must not be public.

## Decision

- Link individual entries of `~/.claude` (`CLAUDE.md`, `rules/`, `agents/`, `references/`, `statusline.sh`), never the whole directory. Hooks are built into the store instead (ADR 0007). `~/.codex` follows the same rule, and `~/.codex/AGENTS.md` links to the same file as `~/.claude/CLAUDE.md`, because Codex reads its global instructions only from its own home.
- Skills are grouped by profile directory: `home/.claude/skills/{common,personal,work}/<name>/`, plus `~/.config/dots-work/claude/skills/<name>/` for work skills that must not be public. `nix/agents.nix` links `common` plus the host's profile flat into `~/.claude/skills/<name>`. A name in two profiles is an evaluation error. Pure evaluation cannot read `~/.config/dots-work/`, so an activation script links the work-profile skills and fails on a name collision.
- `settings.json` (plugins, marketplaces, env, permissions, hooks) and MCP config are generated at activation by deep-merging a common JSON with the profile's JSON with jq, concatenating and de-duplicating arrays, and written as regular files. If the work file is missing, the common file is used alone with a warning.
- Third-party skills and plugins stay with Claude Code's marketplaces.

## Consequences

- The profile is expressed by where a file lives; there is no exclusion list to maintain.
- Settings changed inside Claude Code are overwritten by the next switch. The switch shows the diff first, and lasting changes go into the source JSON.
- Orca merges its own hook entries into `settings.json` at app start and does not restore them until it restarts. Orca, Claude Code, and the generator each read the file and later write it whole, so one can lose another's write (`spec/settings_writers.tla`). The generator writes Orca's entries itself rather than carrying them over from the file it read, so a switch never cuts Orca off from agent status and permission requests. A stale write by Claude Code or by Orca's own theme sync can still drop them; those races are between other tools.
- On macOS the guard hooks and `permissions.deny` are also written to a managed-settings drop-in that no other tool is assumed to write (ADR 0007), so a stale write by Orca or Claude Code cannot remove them, unless a higher managed source hides the drop-in (possible on `work-mac`). `wsl` has no drop-in. Other keys stay in `settings.json`, because managed scope changes their behaviour (managed `enabledPlugins` cannot be turned off).
- Codex writes trust levels into `config.toml` through symlinks, so `config.toml` is written as a regular file too.
- Profiles can add array entries, such as work-only `permissions.deny` rules for cloud, cluster, and infrastructure CLIs. jq's plain `*` would replace the common array instead, which is why the merge concatenates.
- Hooks are referenced by store path in the generated `settings.json` (see ADR 0007).
- CI cannot see the work profile, so it merges against `profiles/work.example/`.

## Alternatives considered

- **Link the whole `~/.claude` directory**: runtime state would land in the repository. Rejected.
- **Store-linked `settings.json` built with `builtins.toJSON`**: read-only. Claude Code's docs say a change made in Claude Code then lasts only for the session, and Orca could not merge its hooks. Rejected.
- **One full `settings.json` per host**: shared hooks and permissions would drift. Rejected.
- **apm (Agent Package Manager)**: lockfile and hashes for third-party skills, plugins, and MCP. Pre-1.0, and multiple user-scope manifests are unverified. Revisit when third-party plugins need version pinning.
