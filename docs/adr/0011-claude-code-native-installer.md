# ADR 0011: Claude Code from its native installer, not from Nix

- Status: Accepted
- Date: 2026-11-25

## Context

P8 puts a nixpkgs package ahead of any other installer. nixpkgs has `claude-code` (2.1.330 at the time of writing, while the native installer had already moved to 2.1.332, measured), and its package sets `DISABLE_AUTOUPDATER=1` (`pkgs/by-name/cl/claude-code/package.nix`), so a Nix-installed Claude Code changes only when `flake.lock` does. Claude Code releases often, and this design relies on behaviour that arrives in specific versions (for example `onFailure` on hooks, v2.1.295 or later). Claude Code's setup docs recommend the native installer, which installs into `~/.local/share/claude/versions/`, links `~/.local/bin/claude`, and updates itself in the background; Homebrew, WinGet, apt, dnf, and apk installs do not auto-update by default.

## Decision

- Claude Code is installed with its native installer (`curl -fsSL https://claude.ai/install.sh | bash -s stable`) on every host, `wsl` included, and updates itself. It is a stated exception to P8.
- A home-manager activation step runs the installer only when `~/.local/bin/claude` is missing, so a switch on a machine that already has it changes nothing and the bootstrap needs no extra step.
- `settings.common.json` sets `autoUpdatesChannel: "stable"`, so hosts follow releases that are typically about a week old and skip those with major regressions, rather than the default `latest`. The installer is given `stable` too, so the first version is from the same channel.

## Consequences

- Claude Code's version is not pinned by `flake.lock` and can differ between hosts for a while. A fix that lands only in `latest` reaches these hosts about a week later.
- The installer runs from the network with the same trust as the bootstrap's own `curl`. On `work-mac` it goes through the corporate proxy; whether it trusts the corporate CA at that point is **Unverified**, as for the bootstrap's other first-run downloads.
- `~/.local/bin` must be on PATH for every shell, which `$ZDOTDIR/.zshenv` already does.

## Alternatives considered

- **nixpkgs `claude-code`**: pinned and identical on every host, but updates only with `flake.lock`, so fixes and features arrive days to weeks late. Rejected.
- **Homebrew cask with `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1`**: macOS only, so `wsl` would still need another method. Rejected.
