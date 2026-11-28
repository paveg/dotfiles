# ADR 0004: GitHub authentication through ghtkn, split by profile

- Status: Accepted
- Date: 2026-11-25

## Context

Agents call `gh` and git all day. A long-lived token stored by `gh auth login` or exported in the shell would be reachable by every agent process. The previous setup wrapped `gh` in a zsh function that ran `ghtkn exec`, which non-interactive shells never load, so agents silently bypassed it. Work and personal use different GitHub Apps.

## Decision

- Every host gets GitHub tokens from ghtkn; `gh auth login` is never used.
- `gh` is an executable wrapper (`nix/gh.sh`, built with `writeShellApplication`) that calls the real binary by store path. The real `gh` is not in `home.packages`.
  - With `GH_TOKEN` or `GITHUB_TOKEN` holding more than whitespace, it runs the real `gh` directly.
  - It does the same for a first argument that `gh` runs with no auth check and no API call, such as help, `--version` and shell completion (the list is in `nix/gh.sh`), so a locked agent leaves them working. Completions that call the API, such as `pr create --reviewer`, then get no token.
  - Otherwise it runs `ghtkn exec -e GH_TOKEN:<app> -- <real gh>`, reading `<app>` from `~/.config/ghtkn/gh-app`.
  - On exit code 111 it tells the user to run `ghtkn agent unlock --enable-refresh`.
- Profiles:
  - Work: `ghtkn.yaml` with none / read / git / write apps, kept in the work profile. The none app is listed first, but `static.env` sets `GHTKN_APP` to the read app for aqua, so a direct `ghtkn exec` that names no app gets the read app. Work repositories use HTTPS with `ghtkn git-credential`, scoped by `includeIf`. `git-credential` picks its app from `git_owners` in `ghtkn.yaml` before `GHTKN_APP`, so the work `ghtkn.yaml` names the write app for the work owner, with `credential.useHttpPath true` in `work.gitconfig`; otherwise pushes would get a read-only token. aqua reads its private registry through ghtkn.
  - Personal: a personal GitHub App, created before the first switch of the personal Mac. `ghtkn.yaml` is rendered by `op inject` from a committed template whose client IDs are `op://` references. Git transport is SSH through 1Password.
- The work `includeIf` that scopes the credential helper names the org directory, so it lives in the work profile (`git/include.gitconfig`), which the public gitconfig includes; git ignores the include when the file is absent.
- The `GH_TOKEN` pass-through exists only for callers that already hold a short-lived token, such as CI.
- Both `ghtkn.yaml` files set `backend.type: agent`; ghtkn's default backend is the OS keyring.
- `ghtkn exec` never starts the device flow, so bootstrap runs `ghtkn auth` once per app, after `ghtkn agent unlock --enable-refresh` has set the passphrase (no token can be obtained from a locked agent). Exit code 111 means either that the agent is locked or that the app is not authenticated yet.
- The ghtkn agent runs from `launchd.user.agents` on macOS and a systemd user service on WSL2.
- `GITHUB_TOKEN`, `AQUA_GITHUB_TOKEN`, and `AQUA_KEYRING_ENABLED` are never set, because aqua then ignores ghtkn.

## Consequences

- Agents in `zsh -c` get the same short-lived tokens as interactive shells.
- No org name appears in this repository: it lives in `gh-app` and `ghtkn.yaml` in the profile.
- Creating the personal GitHub App is the first rollout step; without it `gh` does not work on personal machines.
- Running the ghtkn agent on WSL2 is unverified.

## Alternatives considered

- **zsh function wrapper (status quo)**: invisible to non-interactive shells. Rejected.
- **`gh auth login`**: stores a long-lived token. Rejected.
