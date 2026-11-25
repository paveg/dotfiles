# ADR 0008: Repository checks with treefmt-nix, run by lefthook and CI

- Status: Accepted
- Date: 2026-11-25

## Context

The design asks for gitleaks before every commit and in CI, but did not say what installs the commit hook. The repository will hold Nix, shell, zsh, Lua, TOML, YAML, JSON, Markdown, and GitHub Actions workflows. The formatters and linters on PATH today come from Homebrew and devbox global, both of which the design removes.

## Decision

- The flake defines one `formatter` with treefmt-nix and exposes the same configuration as a `checks` entry, so `nix fmt`, `nix flake check`, `just check`, and CI run the same pinned versions from `flake.lock`.

| Files | Tools |
|---|---|
| Nix | nixfmt, statix, deadnix |
| bash in `scripts/` | shfmt, shellcheck (hooks get shellcheck from `writeShellApplication` at build time, ADR 0007) |
| zsh startup files | `zsh -n` as a check (shellcheck does not support zsh) |
| Lua (`nvim`) | stylua |
| TOML / YAML | taplo / yamlfmt |
| Markdown | rumdl |
| GitHub Actions | actionlint, zizmor |

- Which of these tools treefmt-nix ships as a module, and which need a custom formatter entry, is **Unverified** until the flake is written.
- gitleaks is not a formatter and stays outside treefmt. `gitleaks` and `lefthook` come from `nix/packages.nix`.
- lefthook runs gitleaks on staged changes, `git diff --cached --check`, and the treefmt check in this repository only. `--check` rejects staged leftover conflict markers and whitespace errors (it exits 2 on a staged conflict marker, measured); over this repository's tracked files it currently reports nothing (measured). `lefthook install` is a bootstrap step.
- CI runs gitleaks over the full history and `nix flake check`, so a missing local hook cannot let a leak or a format error through.

## Consequences

- A commit made without lefthook installed still meets CI's gitleaks and format gate before merge.
- Other repositories keep their own hooks; this repository sets no global `core.hooksPath`.
- Adding a file type means adding its tool to the treefmt configuration and to the table above.

## Alternatives considered

- **Global `core.hooksPath` with gitleaks**: covers every repository an agent commits in, but disables each repository's own `.git/hooks` (husky, lefthook) unless a wrapper chains them. Rejected.
- **git-hooks.nix**: integrates with flake checks, but installs hooks only when a `nix develop` shell runs, which is the shell-hook dependency P1 rules out. Rejected.
- **CI only**: thinnest, but a leaked secret is found only after it is pushed. Rejected.
