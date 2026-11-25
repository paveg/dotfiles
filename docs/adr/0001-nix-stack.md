# ADR 0001: Determinate Nix, nix-darwin, and home-manager

- Status: Accepted
- Date: 2026-11-25

## Context

The previous setup combined chezmoi, devbox global, mise, aqua, and Homebrew. Packages floated on `@latest` with no committed lock, and host differences lived in Go templates switched by an environment variable. The new setup must rebuild macOS and WSL2 hosts from locked definitions and keep configuration readable by agents.

## Decision

- Install Nix with Determinate Nix on every host, including WSL2.
- macOS: nix-darwin with home-manager as a darwin module. nix-darwin sets `nix.enable = false` (Determinate's nix-darwin module does this automatically) and manages casks and launchd agents.
- WSL2: standalone home-manager.
- Configuration stays in plain files linked with `mkOutOfStoreSymlink`, using absolute string paths to the checkout.
- `flake.lock` is committed.

## Consequences

- One lock file covers every host.
- nix-darwin's `nix.*` options and Linux builder are unavailable; Nix settings go through Determinate.
- WSL2 needs systemd enabled before installation; otherwise the installer stops with `Wsl2SystemdNotActive`.
- Absolute symlink paths fix the checkout location per machine. Adding or removing a linked file needs a switch.
- `nix flake check` does not cover darwin or home configurations, so CI builds them explicitly.

## Alternatives considered

- **chezmoi + devbox global (status quo)**: no lock, no casks, template logic. Rejected.
- **Upstream Nix on WSL2**: the Determinate installer offers it only behind `--prefer-upstream-nix`, which its README calls unsupported and possibly removed. Rejected.
- **home-manager `programs.*` modules**: generated config is hard for agents to read. Rejected, except for shell integration that has no other form.
