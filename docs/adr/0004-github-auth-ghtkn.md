# ADR 0004: GitHub authentication through ghtkn, split by profile

- Status: Accepted
- Date: 2026-11-25

## Context

Agents call `gh` and git all day. A long-lived token stored by `gh auth login` or exported in the shell would be reachable by every agent process. The previous setup wrapped `gh` in a zsh function that ran `ghtkn exec`, which non-interactive shells never load, so agents silently bypassed it. Work and personal use different GitHub Apps.

## Decision

- Every host gets GitHub tokens from ghtkn; `gh auth login` is never used.
- `gh` is an executable wrapper (`writeShellScriptBin "gh"`) that calls the real binary by store path. The real `gh` is not in `home.packages`.
  - With `GH_TOKEN` or `GITHUB_TOKEN` set, it runs the real `gh` directly.
  - Otherwise it runs `ghtkn exec -e GH_TOKEN:<app> -- <real gh>`, reading `<app>` from `~/.config/ghtkn/gh-app`.
  - On exit code 111 it tells the user to run `ghtkn agent unlock --enable-refresh`.
- Profiles:
  - Work: `ghtkn.yaml` with none / read / git / write apps (none first, so the default carries no permission), kept in the work profile. Work repositories use HTTPS with `ghtkn git-credential`, scoped by `includeIf`. aqua reads its private registry through ghtkn.
  - Personal: a personal GitHub App, created before the first switch of the personal Mac. `ghtkn.yaml` is rendered by `op inject` from a committed template whose client IDs are `op://` references. Git transport is SSH through 1Password.
- The work `includeIf` that scopes the credential helper names the org directory, so it lives in the work profile (`git/include.gitconfig`), which the public gitconfig includes; git ignores the include when the file is absent.
- The `GH_TOKEN` pass-through exists only for callers that already hold a short-lived token, such as CI.
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
