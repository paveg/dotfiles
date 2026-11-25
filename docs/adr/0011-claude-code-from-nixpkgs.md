# ADR 0011: Claude Code from nixpkgs

- Status: Accepted. Replaces this ADR's first version (native installer on the `stable` channel), withdrawn the same day after a post-merge review by an agent.
- Date: 2026-11-25

## Context

Claude Code changes often, and this design relies on behaviour that arrives in specific versions (for example `onFailure` on hooks, v2.1.295 or later). Its setup docs recommend the native installer, which updates itself in the background, with a `latest` channel and a `stable` channel ("typically about one week old, skipping releases with major regressions"). nixpkgs has `claude-code`, whose wrapper sets `DISABLE_AUTOUPDATER=1`, so the Nix-installed binary does not update in the background (`claude update` still works, per the setup docs). `claude-code` is unfree, so it has to be allowed by name.

On 2026-11-25 the channels and nixpkgs stood at `stable` 2.1.326, nixpkgs 2.1.330, and `latest` 2.1.332 (measured). The nixpkgs wrapper also does work this design would otherwise have to repeat (`pkgs/by-name/cl/claude-code/package.nix`):

- it puts `ripgrep` and `procps` on the program's PATH, and on Linux also `bubblewrap` and `socat`, which the sandbox needs there;
- it defaults `CLAUDE_CODE_CERT_STORE` to `system` and, on macOS, copies `NIX_SSL_CERT_FILE` into `NODE_EXTRA_CA_CERTS` when the first is set and the second is not; whether that is what `work-mac` needs behind the corporate proxy is **Unverified**;
- with `home-manager.useUserPackages = true` its `claude` lands in `/etc/profiles/per-user/$USER/bin` on macOS (`~/.nix-profile/bin` on `wsl`), which `$ZDOTDIR/.zshenv` and the PATH planned for the `orca serve` LaunchAgent both include.

## Decision

- Claude Code comes from nixpkgs' `claude-code` in `nix/packages.nix` on every host, following P8, allowed by name as an unfree package. Not implemented yet (PAV-44).
- It updates with `flake.lock`: through the weekly lock-update pull request once that workflow exists (design.md, CI), or a manual update when a fix is needed sooner. A `flake.lock` change triggers `nix.yml`, which builds every host.
- home-manager's `programs.claude-code` module is not used: this design writes `settings.json` itself (ADR 0003). What the module manages besides the package was not checked.

## Consequences

- Once implemented, every host runs the same, pinned version, and an update is built by CI before it reaches a host.
- New releases arrive later than on `latest`; at the time of writing nixpkgs was two releases behind `latest` and four ahead of `stable`.
- Nobody curates out a release with a regression, as `stable` would. No test here runs `claude`, so a broken release is noticed in use and rolled back by reverting `flake.lock`.
- A host that already has the native installer keeps its `~/.local/bin/claude`, which updates itself; it is removed in Rollout step 2 so that only one `claude` exists (the Nix directories come first on PATH, so the Nix one wins meanwhile in shells).

## Alternatives considered

- **Native installer on `stable`** (this ADR's first version): older than nixpkgs at the time of writing; switching an existing install to `stable` downgrades it (the docs say so, "even when that version is older than yours"); `~/.local/bin` is not on the PATH this design plans for the `orca serve` LaunchAgent; the CA and sandbox dependencies above would need handling by hand; and a home-manager activation step would have to download the installer with no `curl` on its PATH. Rejected.
- **Native installer on `latest`**: newest, but unreviewed releases arrive on every host directly, with the same PATH, CA, and sandbox gaps. Rejected.
- **Homebrew cask with `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1`**: this design has Homebrew only on macOS (through nix-homebrew), so `wsl` would need another method. Rejected.
