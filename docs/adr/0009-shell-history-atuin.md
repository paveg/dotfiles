# ADR 0009: Shell history in atuin, kept free of tokens before an AI reads it

- Status: Accepted
- Date: 2026-11-25

## Context

The owner wants an AI to read the interactive command history and suggest where work can be made faster. zsh's own history stores only the command text. Command history can also carry tokens typed on the command line, and the history is useful to an AI only if no token reaches it.

## Decision

- Interactive history goes to atuin, which stores each command with its directory, exit code, duration, and session in SQLite. `Ctrl+r` searches it. zsh's own history stays in `$XDG_STATE_HOME/zsh/history` as a fallback.
- Tokens are kept out in five layers, detailed in the design ("Shell history (atuin)"):
  1. commands never carry tokens (`op run`, `ksm exec`, `ghtkn exec`);
  2. atuin's `secrets_filter` stays on;
  3. `history_filter` lists commands specific to this setup that take secrets as arguments, such as `ksm profile init`;
  4. `auto_sync = false`, set explicitly;
  5. agents cannot read atuin's database (a `Read(...)` deny rule); an AI receives only an `atuin history list` export that gitleaks has scanned and found clean.

## Consequences

- The history holds human operations only, because agents run commands through `zsh -c`, which atuin does not record. Agent behaviour is analysed from session transcripts instead.
- A token that matches no pattern and is typed on the command line is stored in atuin. The gitleaks scan of the export stops it before an AI sees it, but it stays on the local disk.
- Disabling sync means history does not follow the owner across machines.
- Whether the nixpkgs version of atuin carries the same secret patterns as its main branch is unverified.

## Alternatives considered

- **zsh history only**: no exit codes, durations, or directories, so the analysis has little to work with. Kept only as the fallback.
- **atuin with sync to atuin's server**: history across machines, but the history leaves the machine. Rejected. A self-hosted server can be revisited if cross-machine history becomes necessary.
- **Let the AI read the database directly**: simplest, but nothing stops a token that slipped past the filters. Rejected.
