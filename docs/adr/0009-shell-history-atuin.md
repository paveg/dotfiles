# ADR 0009: Shell history in atuin, kept free of tokens before an AI reads it

- Status: Accepted
- Date: 2026-11-25

## Context

The owner wants an AI to read the interactive command history and suggest where work can be made faster. zsh's own history stores only the command text. Command history can also carry tokens typed on the command line, and the history is useful to an AI only if no token reaches it.

## Decision

- Interactive history goes to atuin, which stores each command with its directory, exit code, duration, and session in SQLite under `ATUIN_HOME=$XDG_DATA_HOME/atuin` (atuin's own default is `~/.atuin`). `Ctrl+r` searches it.
- zsh keeps history in memory only. A zsh history file would hold every command unfiltered, so atuin is the only history on disk.
- Tokens are kept out in five layers, detailed in the design ("Shell history (atuin)"):
  1. commands never carry tokens (`op run`, `ksm exec`, `ghtkn exec`);
  2. atuin's `secrets_filter` stays on; a command that matches it is not saved at all;
  3. `history_filter` adds what that filter misses: commands specific to this setup that take secrets as arguments, such as `ksm profile init`, and assignments to variables named like tokens, secrets, passwords, or keys;
  4. `auto_sync = false` and `update_check = false`, set explicitly;
  5. an AI receives the history only through an export that gitleaks has scanned and found clean. A `Read(...)` deny rule on atuin's data directory is a tripwire for file tools and common Bash reads, not a boundary: an agent could still run `atuin` or `sqlite3` itself until the sandbox's `denyRead` is enabled (ADR 0007).

## Consequences

- The history holds human operations only, because agents run commands through `zsh -c`, which atuin does not record. Agent behaviour is analysed from session transcripts instead.
- A token that matches no pattern and is typed on the command line is stored in atuin. The gitleaks scan of the export stops it before an AI sees it, but it stays on the local disk.
- Disabling sync means history does not follow the owner across machines.
- Whether the nixpkgs version of atuin carries the same secret patterns as its main branch is unverified.

## Alternatives considered

- **zsh history only**: no exit codes, durations, or directories, so the analysis has little to work with. Rejected.
- **zsh history file as a fallback to atuin**: survives an atuin failure, but bypasses every filter. Rejected; zsh keeps history in memory only.
- **atuin with sync to atuin's server**: history across machines, but the history leaves the machine. Rejected. A self-hosted server can be revisited if cross-machine history becomes necessary.
- **Let the AI read the database directly**: simplest, but nothing stops a token that slipped past the filters. Rejected.
