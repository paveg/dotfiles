# dotfiles

Personal dotfiles, built for AI-native development.

## Principles

- **Agents are first-class users.** Configuration for coding agents (instructions, rules, skills, hooks) lives here alongside shell and editor config, and is versioned the same way.
- **Readable by humans and agents alike.** Every directory should be understandable from its own files; `AGENTS.md` is the entry point for agents.
- **Reproducible over clever.** A fresh machine should reach a working state with one documented command.
- **No secrets in the repo.** Credentials come from a secret manager at runtime, never from committed files.

## Status

Work in progress. The layout and bootstrap procedure will be documented here as they land.
