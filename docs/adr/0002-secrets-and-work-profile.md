# ADR 0002: Secrets in vaults, work profile in Keeper

- Status: Accepted (Keeper Secrets Manager availability to be confirmed with company IT)
- Date: 2026-11-25

## Context

Secrets used to live in plain-text local files, and company connection settings (an internal API endpoint, internal plugin marketplaces) were committed to a public repository. The new setup must keep secrets off disk and company information out of this repository, while still rebuilding a work machine from scratch.

The company provides Keeper; the personal vault is 1Password.

## Decision

- Personal secrets: 1Password. Commands receive tokens through `op run` (environment) or `op inject` (files).
- Company secrets: Keeper Secrets Manager. Commands receive tokens through `ksm exec` (environment) or `ksm interpolate` (files, written with mode 0600).
- Company configuration files (Claude Code work settings, internal MCP config, work gitconfig, ghtkn work apps) are stored as attachments on a Keeper record and pulled into `~/.config/dots-work/` (untracked) with `ksm secret download`. Edits are pushed back with `ksm secret upload`.
- Nothing is exported at shell start-up; only the command that needs a secret gets it.
- Run-time forms (`op run`, `ksm exec`) are preferred. A secret is rendered to a file only for a tool that cannot read it from the environment; the file is mode 0600, untracked, and listed in the design.
- `op://` references for the personal profile may be committed: they are pointers that need the account to resolve. Anything that identifies the company, including `keeper://` references, internal endpoints, and org names, lives only in the work profile.
- Non-secret work variables that every shell needs live in `~/.config/dots-work/env/static.env`, which `.zshenv` sources when present.
- gitleaks runs as a pre-commit hook and in CI.

## Consequences

- Company information never reaches a personal GitHub account.
- Personal and company secrets use the same two shapes (inject into a command, render into a file), so scripts differ only in the CLI they call.
- The KSM device credential stays on disk; installed with keyring support, it is stored in the macOS Keychain.
- Editing a work config file requires pushing it back to Keeper; otherwise the next pull overwrites the edit.
- Keeper's docs do not say whether Secrets Manager needs admin enablement or an extra license. If it is unavailable, the work profile stays local to the work machine and is recreated by hand on a new one.

## Alternatives considered

- **Private git repository for company config**: reproducible, but puts company information on a personal GitHub account. Rejected.
- **Local-only work profile**: thinnest, but lost with the machine. Kept as the fallback.
- **1Password for company files too**: mixes company data into a personal vault. Rejected.
- **sops-nix / agenix**: adds encryption keys to manage, with no gain over the vaults. Not now.
