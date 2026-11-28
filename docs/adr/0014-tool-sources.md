# ADR 0014: Nix for tools, Homebrew casks for macOS apps

- Status: Accepted. Revises P8 in design.md, and amends ADR 0012.
- Date: 2026-11-28

## Context

P8 put every tool on one ladder: a nix-darwin or home-manager module, then a nixpkgs package, then a Homebrew cask through nix-homebrew, then a manual install. On that ladder a macOS app comes from nixpkgs whenever nixpkgs has it. design.md planned Raycast (`raycast`) and Ghostty (`ghostty-bin`) that way, and 1Password through nix-darwin's `programs._1password-gui`. None of them is built yet. At `9d21ac7` both darwin systems have `homebrew.enable = false` and no casks, and neither `system.build.applications` nor the home-manager profile holds an `.app` bundle (measured, `nix eval` and `nix build` of `personal-mac` and `work-mac`).

An app from nixpkgs has three costs:

- It cannot update itself. nix-darwin copies it out of the store with `rsync --chmod=-w` (`modules/system/applications.nix:84-101`; `modules/programs/_1password-gui.nix:24-46` for 1Password), so updates arrive only with a `flake.lock` update.
- nixpkgs lags the vendors. Measured on 2026-11-28: nixpkgs `raycast` 2.10.1.0 against cask 2.13.1.0, and `karabiner-elements` 15.7.0 against 16.3.0. `ghostty-bin` and `_1password-gui` matched their casks (1.4.0 and 8.12.46).
- An app in `/Applications/Nix Apps` can make a switch over SSH fail. Every activation runs `ensureAppManagement`, which touches each bundle in that folder. When a touch fails over SSH, activation exits 1 unless programs run over SSH have Full Disk Access (`applications.nix:23-41`). That breaks an unattended switch from Orca (ADR 0010).

P8 also said nothing about language package managers. ADR 0012 puts `uv`, `rustup`, and mise with its runtimes on every host, so `uv tool install`, `cargo install`, `go install`, `pnpm add -g`, `npm -g`, and `gem install` are each one command away. A tool installed that way is outside `flake.lock` and outside `tests/licenses.sh`.

## Decision

The owner decided on 2026-11-28:

- A tool that is not a macOS GUI app comes from Nix: a nix-darwin or home-manager module, then a nixpkgs package. A manual install comes last.
- A macOS GUI app comes from a Homebrew cask through nix-homebrew. It comes from nixpkgs only when no cask exists. When the vendor ships its own tap, as Orca does, the cask comes from that tap.
- A global CLI tool comes from Nix, not from a language package manager (`uv tool install`, `cargo install`, `go install`, `pnpm add -g`, `npm -g`, `gem install`). A language package manager installs a global tool only when nixpkgs lacks it, and that install gets an entry under `outsideNix.<host>` in `nix/licenses.nix` for each host that has it, as MoonBit has (ADR 0012). An entry in the global mise config with a package-manager backend (`npm:`, `cargo:`, `go:`, `pipx:`, `gem:`) is the same kind of install.
- Project dependencies (`uv add`, `cargo add`, `pnpm add`) belong to each project and are out of scope.
- A tool on a later rung still names why the earlier ones do not work.

The planned macOS apps change source as follows. Each licence is the one its `outsideNix` entry records:

| App | Before | After | Licence | Source of the licence |
|---|---|---|---|---|
| 1Password | `programs._1password-gui` | cask `1password` | `unfree` | nixpkgs `_1password-gui` |
| Raycast | nixpkgs `raycast` | cask `raycast` | `unfree` | nixpkgs `raycast` |
| Ghostty | nixpkgs `ghostty-bin` | cask `ghostty` | `mit` | nixpkgs `ghostty-bin` |
| Karabiner-Elements | cask `karabiner-elements` | unchanged | `unlicense` | nixpkgs `karabiner-elements` |
| Orca | cask `stablyai/orca/orca` | unchanged | `mit` | `stablyai/orca` on GitHub |

The nixpkgs licences are `meta.license` at the locked nixpkgs (measured). A cask carries no licence field. All five apps go on `personal-mac` and `work-mac`, and none of the licences is non-commercial.

Three planned installs stay in Nix, because none of them is a GUI app: the 1Password CLI (`programs._1password`, which installs `/usr/local/bin/op`), Tailscale (`services.tailscale`, the open-source `tailscaled` of ADR 0010), and the font (`udev-gothic-nf` through `fonts.packages`).

## Consequences

- No app comes from nixpkgs, so `/Applications/Nix Apps` holds no bundle. `ensureAppManagement` still runs on every switch: nix-darwin adds it to `system.checks` with no condition (`applications.nix:10-21`) and calls it at line 23. With no `*.app` directory in the folder, it touches nothing and returns 0 (lines 12-20). The switch then neither resets App Management nor aborts over SSH. Measured: the function, cut from the built `personal-mac` activate script and pointed at a stand-in folder, returned 0 with no folder, with an empty folder, and with a writable bundle. It returned 1 with a bundle it could not write into.
- A host that already has an app in `/Applications/Nix Apps` keeps the check active for one more switch. Checks run before the applications step (`modules/system/activation-scripts.nix:116` and `:121`), and only that step's `rsync --delete` removes the old copy. So the first switch after the last nixpkgs app leaves runs at the desk. No such folder exists on this Mac (measured), and no configuration in this repository has put an app there.
- The switching terminals no longer need App Management, so the bootstrap's checklist and the acceptance criteria drop it.
- A switch installs a missing cask and does not upgrade an installed one. nix-darwin passes `--no-upgrade` to `brew bundle` while `homebrew.onActivation.upgrade` keeps its default `false` (`modules/homebrew.nix:132-134` and `:195`). The four homebrew/cask casks set `auto_updates` (measured, `brew info --cask --json=v2`), so those apps update themselves. Their versions then differ between hosts, and no diff in this repository shows an update.
- 1Password now arrives through `brew bundle`, and the bootstrap needs it before step 6. nix-homebrew sets Homebrew up at the start of nix-darwin's Homebrew step (`lib.mkBefore`, nix-homebrew `modules/default.nix:597-606`), so the first switch installs the casks. That file was read at nix-homebrew `b279e78`, its default branch on 2026-11-28, because nix-homebrew is not a flake input yet.
- Whether `brew bundle` installs a cask over SSH without a permission prompt is **Unverified**.
- The unfree allowance shrinks to the packages nixpkgs still builds: `claude-code` and `_1password-cli`. `raycast` and `_1password-gui` leave it with their apps.
- The KSM CLI on `work-mac` is the first tool the language-package-manager exception may cover. nixpkgs has no attribute for it (measured: of the ten attribute names that contain `keeper` or start with `ksm`, none is Keeper's). An install with a language package manager gets an `outsideNix.work-mac` entry. A local derivation would keep it in Nix. design.md leaves that choice open.
- `tests/licenses.sh` does not find a language package manager install. Its `outsideNix` entry is kept by hand, as the Windows-side font's is, and nothing fails when the entry is missing.
- `wsl` does not change: it has no Homebrew, and its Windows apps come from winget.

## Alternatives considered

- **Keep P8's order, with nixpkgs before casks for apps**: app versions stay in `flake.lock`, but all three costs above stay too. Rejected.
- **Full Disk Access for programs run over SSH**: `ensureAppManagement` would pass over SSH with nixpkgs apps installed. Rejected, as before, because it gives every SSH session access to the whole disk.
- **Casks for CLI tools too**: one source on macOS, but `wsl` has no Homebrew, so each tool would need a second source there. ADR 0011 rejected the Claude Code cask for the same reason. Rejected.
- **Language package managers for global tools**: releases arrive sooner, but the tools sit outside the lock and the licence check. Rejected, except where nixpkgs lacks the tool.
