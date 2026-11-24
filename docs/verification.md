# Verification log

Evidence behind the factual statements in [`design.md`](design.md), collected on 2026-11-25. "Measured" means a command was run on a real machine; "Source" means an official document or source file was read. Statements marked **Unverified** in the design are not listed here.

## Shell and PATH

| Statement | Result | Evidence |
|---|---|---|
| Tools activated by a `.zshrc` hook are invisible to `zsh -c` | Holds | Measured in a project whose `mise.toml` declares a tool: `env -i HOME=$HOME PATH=/usr/bin:/bin zsh -c 'command -v <tool>'` did not find it; the same command after `eval "$(mise hook-env -s zsh)"` resolved it under mise's install directory (positive control) |
| mise shims resolve project tools without a hook | Holds | Measured: `env -i HOME=$HOME PATH=$HOME/.local/share/mise/shims:/usr/bin:/bin zsh -c '<tool> --version'` in that project printed the version |
| Claude Code's Bash tool replays the interactive shell, aliases included | Holds | Measured: in a Claude Code Bash tool shell, `ls` ran the `eza --icons` alias, and `mise` was a shell function sourced from `~/.claude/shell-snapshots/` |
| Global tools whose PATH is set in `.zshenv` resolve from `zsh -c` started with launchd's default PATH | Holds | Measured: `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -c 'command -v gh ghq fzf rg'` resolved all four, exit 0 |
| An app launched from the Dock starts with launchd's default PATH | Holds | Measured: `launchctl print gui/<uid>/application.<terminal app>` showed `PATH => /usr/bin:/bin:/usr/sbin:/sbin` |
| `useUserPackages = true` installs into `/etc/profiles/per-user/$USER/bin` | Holds | Source: home-manager `nixos/common.nix`; nix-darwin `modules/users/default.nix`; home-manager manual, nix-darwin installation |
| Only shell initialization puts that directory on PATH | Holds | Source: nix-darwin `modules/environment/default.nix` (`set-environment`, sourced from `/etc/zshenv`, `/etc/bashrc`, fish) |
| `launchctl config user path` applies to all users and needs a reboot | Holds | Measured: `launchctl help config` ("modifies the configuration for all user domains. You must reboot") |

## Git

| Statement | Result | Evidence |
|---|---|---|
| `includeIf "gitdir:..."` applies to linked worktrees of a matching repository, wherever the worktree lives | Holds | Measured (git 2.56.0, isolated `HOME`): main checkout, `.worktrees/b1`, and `~/worktrees/b2` all resolved the work email; a repository under another owner resolved the personal one |
| git silently ignores an `[include]` whose file does not exist | Holds | Measured: a global config including a missing path returned its own `user.email`, exit 0 |

## Nix, nix-darwin, home-manager

| Statement | Result | Evidence |
|---|---|---|
| `mkOutOfStoreSymlink` with a flake-relative path points into the store | Holds | Measured: inside a flake, `toString ./home/zshrc` evaluated to `/nix/store/...-source/home/zshrc`. Source: home-manager `modules/files.nix`; issues #2085, #2660, #9052 |
| `nix flake check` neither evaluates nor builds `darwinConfigurations` / `homeConfigurations` | Holds | Measured: outputs set to `throw` passed with `all checks passed!` and exit 0; a `nixosConfigurations` control failed with exit 1. Source: NixOS/nix `src/nix/flake.cc` ("Known but unchecked community attribute") |
| A GitHub-hosted macOS runner can build a darwin system | Holds | Source: nix-darwin's own CI on `macos-15` builds `system.build.toplevel` |
| nix-darwin's homebrew module does not install Homebrew; without it, casks are skipped | Holds | Source: nix-darwin `modules/homebrew.nix` ("enabling this option does not install Homebrew", "Homebrew is not installed, skipping...") |
| Pure evaluation cannot read absolute paths outside the flake, such as `~/.config` | Holds | Measured: `nix eval --pure-eval --expr 'builtins.readDir "<home>/.config"'` failed with "access to absolute path ... is forbidden in pure evaluation mode" |
| nix-darwin refuses to activate with `nix.enable` on under Determinate | Holds | Source: nix-darwin `modules/system/checks.nix` ("Determinate detected, aborting activation") |
| Upstream Nix through the Determinate installer is unsupported | Holds | Source: DeterminateSystems/nix-installer README ("isn't a supported configuration", "we may remove it in a future release") |
| Determinate Nix supports WSL2 with systemd | Holds | Source: nix-installer README platform table; `Wsl2SystemdNotActive` planner error |
| Determinate Nixd exports Keychain certificates at start-up and must be restarted after changes | Holds | Source: docs.determinate.systems, Determinate Nixd ("On startup, the system's Keychain certificates are exported for Nix." / "If the certificate store changes, you need to restart Determinate Nixd.") |

## Nix and TLS

Checked against Nix 2.33.0 and nixpkgs 26.05pre.

| Statement | Result | Evidence |
|---|---|---|
| Nix's own downloads use `ssl-cert-file` | Holds | Source: nix `src/libstore/filetransfer.cc` (`CURLOPT_CAINFO` from `settings.caFile`) |
| The configured `ssl-cert-file` wins over `NIX_SSL_CERT_FILE` | Holds (contrary to the manual) | Measured: with both set (setting through `NIX_CONFIG`), the setting's value was used. Source: nix `globals.cc` (the environment only sets the default) |
| `builtin:fetchurl` uses the daemon's `ssl-cert-file` | Holds | Source: nix `derivation-builder.cc`, `builtins/fetchurl.cc` |
| nixpkgs `fetchurl` with a known hash skips TLS verification | Holds | Source: nixpkgs `pkgs/build-support/fetchurl/default.nix`, `builder.sh` |
| `fetchgit` and Go / cargo / npm fetchers take `NIX_SSL_CERT_FILE` from the daemon environment | Holds | Source: nixpkgs `lib/fetchers.nix` (`proxyImpureEnvVars`), `fetchgit/nix-prefetch-git` |
| The Linux sandbox exposes `ssl-cert-file` only at `/etc/ssl/certs/ca-certificates.crt` | Holds | Source: nix `linux-derivation-builder.cc` |
| Some fixed-output derivations hard-code nixpkgs' cacert | Holds | Source: nixpkgs `fetch-yarn-deps`, `build-bazel-package`, `docker`, `fetchrepoproject` |
| `git+https://` inputs and `builtins.fetchGit` run the `git` binary | Holds | Source: nix tag 2.33.0 `src/libfetchers/git-utils.cc:602` (`runProgram` with `.program = "git"`) |
| `hg+https://` passes no CA to `hg`; git LFS uses Nix's own transfer | Holds | Source: nix `mercurial.cc`, `git-lfs-fetch.cc` |
| On Linux, Nix defaults `ssl-cert-file` to `/etc/ssl/certs/ca-certificates.crt`, and the daemon unit sets no `NIX_SSL_CERT_FILE` | Holds (not run on WSL2) | Source: nix `globals.cc` (`getDefaultSSLCertFile`), `misc/systemd/nix-daemon.service.in` |

## 1Password

| Statement | Result | Evidence |
|---|---|---|
| SSH key approvals are per key and application, per tab in terminals, and last until 1Password locks or quits | Holds | Source: 1password.dev, SSH agent security |
| Approvals survive a lock; only unlocking is asked again | Holds | Source: same page ("your approval will still be in the agent's memory and you'll only be prompted to unlock 1Password") |
| `agent.toml` selects and orders offered keys; the default offers every key in Personal, Private, or Employee vaults | Holds | Source: 1password.dev, SSH agent config file |
| WSL2 forwards SSH to Windows `ssh.exe`, and commit signing works from WSL2 | Holds | Source: 1password.dev, WSL integration |
| The Linux-side `op` in WSL2 cannot use the desktop app integration | Holds | Source: 1password.dev, CLI app integration |

## Keeper

| Statement | Result | Evidence |
|---|---|---|
| `ksm exec` replaces `keeper://` environment values for a command | Holds | Source: docs.keeper.io, Secrets Manager CLI, exec command |
| `ksm interpolate` renders templates and writes output with mode 0600 | Holds | Source: docs.keeper.io, interpolate command |
| `ksm secret download` / `upload` handle record attachments | Holds | Source: docs.keeper.io, secret command |
| With keyring support, the KSM CLI stores its config in the macOS Keychain | Holds | Source: docs.keeper.io, Secrets Manager CLI |

## Claude Code guardrails

| Statement | Result | Evidence |
|---|---|---|
| Bash permission patterns are not a security boundary; `bash -c` is not unwrapped | Holds | Source: code.claude.com/docs/en/permissions ("isn't a security boundary around the program") |
| A PreToolUse hook that exits with another code, cannot start, times out, or prints invalid JSON lets the call proceed, unless `onFailure: "block"` is set | Holds | Source: code.claude.com/docs/en/hooks |
| The previous credential and database guards fail open when `jq` is not on PATH | Holds | Measured: with `env -i PATH=<empty dir>`, the credential guard exited 0 with no output and the database guard exited 127; with a normal PATH both returned `permissionDecision: "deny"` |
| The sandbox covers shell commands only; file tools, MCP servers, and hooks run outside it | Holds | Source: code.claude.com/docs/en/sandboxing |
| The sandbox can deny reads (`filesystem.denyRead`), restrict network by domain, and refuse unsandboxed retries (`allowUnsandboxedCommands: false`), on macOS and WSL2 | Holds | Source: code.claude.com/docs/en/sandboxing |
| `Read(...)` deny rules cover file tools and recognized Bash file commands (`cat`, `head`, `tail`, `sed`, `tee`, redirections) | Holds | Source: code.claude.com/docs/en/permissions |

## Other tools

| Statement | Result | Evidence |
|---|---|---|
| apm (microsoft/apm) is pre-1.0, supports Claude Code user scope, and is in nixpkgs | Holds | Source: microsoft/apm releases (v0.38.1), `docs/.../reference/targets-matrix.md`; nixpkgs `pkgs/by-name/ap/apm-cli/package.nix` |
