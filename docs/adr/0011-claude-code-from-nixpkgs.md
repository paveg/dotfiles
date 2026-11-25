# ADR 0011: Claude Code from nixpkgs

- Status: Accepted. Replaces this ADR's first version (native installer on the `stable` channel), withdrawn the same day after review.
- Date: 2026-11-25

## Context

Claude Code changes often, and this design relies on behaviour that arrives in specific versions (for example `onFailure` on hooks, v2.1.295 or later). Its setup docs recommend the native installer, which updates itself in the background, with a `latest` channel and a `stable` channel ("typically about one week old, skipping releases with major regressions"). nixpkgs has `claude-code`, whose wrapper turns the auto-updater off, so it changes only when `flake.lock` does.

On 2026-11-25 the channels and nixpkgs stood at `stable` 2.1.326, nixpkgs 2.1.330, and `latest` 2.1.332 (measured). The nixpkgs wrapper also does work this design would otherwise have to repeat (`pkgs/by-name/cl/claude-code/package.nix`):

- it puts `ripgrep`, `procps`, `bubblewrap`, and `socat` on the program's PATH, the last two being what the sandbox needs on Linux;
- it sets `CLAUDE_CODE_CERT_STORE=system` and, on macOS, passes Nix's CA bundle as `NODE_EXTRA_CA_CERTS`, which matters behind the corporate proxy on `work-mac`;
- its `claude` lands in the per-user Nix profile, which is already on the PATH of the `orca serve` LaunchAgent and of every shell.

## Decision

- Claude Code comes from nixpkgs' `claude-code` in `nix/packages.nix` on every host, following P8.
- It updates with `flake.lock`: the weekly lock-update pull request, which CI builds and tests before merge, or a manual update when a fix is needed sooner.
- home-manager's `programs.claude-code` module is not used: this design writes `settings.json` itself (ADR 0003). What the module manages besides the package was not checked.

## Consequences

- Every host runs the same, pinned version, and an update passes CI before it reaches a host.
- New releases arrive later than on `latest`; at the time of writing nixpkgs was two releases behind `latest` and four ahead of `stable`.
- Nobody curates out a release with a regression, as `stable` would. A broken release is caught by this repository's tests or rolled back by reverting `flake.lock`.
- A host that already has the native installer keeps its `~/.local/bin/claude`, which updates itself; it is removed at rollout so that only one `claude` exists.

## Alternatives considered

- **Native installer on `stable`** (this ADR's first version): older than nixpkgs at the time of writing; switching an existing install to `stable` downgrades it (the docs say so, "even when that version is older than yours"); `~/.local/bin` is not on the `orca serve` LaunchAgent's PATH; the CA and sandbox dependencies above would need handling by hand; and a home-manager activation step would have to download the installer with no `curl` on its PATH. Rejected.
- **Native installer on `latest`**: newest, but unreviewed releases arrive on every host directly, with the same PATH, CA, and sandbox gaps. Rejected.
- **Homebrew cask with `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1`**: this design has Homebrew only on macOS (through nix-homebrew), so `wsl` would need another method. Rejected.
