# Verification log

Evidence behind the factual statements in [`design.md`](design.md), collected on 2026-11-25. "Measured" means a command was run on a real machine; "Source" means an official document or source file was read. "(by a review agent)" means a review agent read the source or ran the command and the author of this log did not re-open it; treat such a row as one step weaker than its label. Statements marked **Unverified** in the design are not listed here.

## Shell and PATH

| Statement | Result | Evidence |
|---|---|---|
| Tools activated by a `.zshrc` hook are invisible to `zsh -c` | Holds | Measured in a project whose `mise.toml` declares a tool: `env -i HOME=$HOME PATH=/usr/bin:/bin zsh -c 'command -v <tool>'` did not find it; the same command after `eval "$(mise hook-env -s zsh)"` resolved it under mise's install directory (positive control) |
| mise shims resolve project tools without a hook | Holds | Measured: `env -i HOME=$HOME PATH=$HOME/.local/share/mise/shims:/usr/bin:/bin zsh -c '<tool> --version'` in that project printed the version |
| mise's data directory is `MISE_DATA_DIR`, else `$XDG_DATA_HOME/mise`; shims live in its `shims/` | Holds | Source: mise.jdx.dev/directories. Measured: `mise doctor` reports `shims: ~/.local/share/mise/shims` |
| Claude Code's Bash tool replays the interactive shell, aliases included | Holds | Measured: in a Claude Code Bash tool shell, `ls` ran the `eza --icons` alias, and `mise` was a shell function sourced from `~/.claude/shell-snapshots/` |
| Global tools whose PATH is set in `.zshenv` resolve from `zsh -c` started with launchd's default PATH | Holds for the current setup only | Measured: `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -c 'command -v gh ghq fzf rg'` resolved all four, exit 0. Re-run 2026-11-25: all four resolved under devbox global's profile, so this says nothing yet about nix-darwin's per-user profile |
| Under `env -i`, zsh leaves `USER` empty but sets `USERNAME` and `LOGNAME` | Holds | Measured: `env -i HOME=$HOME PATH=/usr/bin:/bin zsh -f -c 'echo "[$USER] [$USERNAME] [$LOGNAME]"'` printed `[] [ryota] [ryota]` |
| nix-darwin adds `/etc/profiles/per-user/$USER/bin` with `$USER` expanded at run time | Holds | Source: nix-darwin `modules/users/default.nix:346` (`mkOrder 900 [ "/etc/profiles/per-user/$USER" ]`); `modules/environment/default.nix:140` (`makeBinPath cfg.profiles`) |
| An app launched from the Dock starts with launchd's default PATH | Holds | Measured: `launchctl print gui/<uid>/application.<terminal app>` showed `PATH => /usr/bin:/bin:/usr/sbin:/sbin` |
| `useUserPackages = true` installs into `/etc/profiles/per-user/$USER/bin` | Holds | Source: home-manager `nixos/common.nix`; nix-darwin `modules/users/default.nix`; home-manager manual, nix-darwin installation |
| Only shell initialization puts that directory on PATH | Holds | Source: nix-darwin `modules/environment/default.nix` (`set-environment`, sourced from `/etc/zshenv`, `/etc/bashrc`, fish) |
| `launchctl config user path` applies to all users and needs a reboot | Holds | Measured: `launchctl help config` ("modifies the configuration for all user domains. You must reboot") |
| In a login shell on macOS, `/etc/zprofile` runs `path_helper` after `~/.zshenv` and moves system directories ahead of entries `.zshenv` prepended | Holds | Measured on this Mac (no nix-darwin), temporary `HOME`: first PATH entry stayed the `.zshenv` one under `zsh -c`, became `/usr/local/bin` under `zsh -lc`; `/etc/zprofile` line 11 runs `path_helper -s` |
| macOS's `/etc/zshrc` sets `HISTFILE` after `.zshenv` runs | Holds | `/etc/zshrc` line 16 on this Mac |
| zsh does not create the parent directory of `HISTFILE`; without it zsh prints `locking failed for <path>: no such file or directory` at exit and saves nothing | Holds | Measured in a temporary `HOME`: no file without the directory (stderr shows the message), file written once the directory existed. An earlier row said "silently"; that measurement had discarded stderr |
| atuin's default home is `~/.atuin` (overridable with `ATUIN_HOME`); `XDG_DATA_HOME/atuin` is used only as a fallback for older installs | Holds | Source: atuin main, `crates/atuin-common/src/dirs.rs` lines 48 and 68, read with `gh api` |
| atuin's `secrets_filter` drops a matching command entirely, and a command starting with a space is not saved | Holds | Source: atuin main, `crates/atuin-client/src/history.rs` lines 797-802 (`should_save`) |
| `zsh -c`, `zsh -lc`, and `zsh -ic` fire no `preexec` / `precmd` / `zshaddhistory` hooks and write no history; an interactive zsh fed commands on stdin does | Holds | Measured (by a review agent) in a temporary `HOME` |

## Git

| Statement | Result | Evidence |
|---|---|---|
| `includeIf "gitdir:..."` applies to linked worktrees of a matching repository, wherever the worktree lives | Holds | Measured (git 2.56.0, isolated `HOME`): main checkout, `.worktrees/b1`, and `~/worktrees/b2` all resolved the work email; a repository under another owner resolved the personal one. Re-run with git 2.50.1 (Apple): the main checkout, `.claude/worktrees/b1`, and a worktree outside the repository resolved the work email, exit 0 |
| git silently ignores an `[include]` whose file does not exist | Holds | Measured: a global config including a missing path returned its own `user.email`, exit 0. Re-run with git 2.50.1: same |

## Nix, nix-darwin, home-manager

| Statement | Result | Evidence |
|---|---|---|
| `mkOutOfStoreSymlink` with a flake-relative path points into the store | Holds | Measured: inside a flake, `toString ./home/zshrc` evaluated to `/nix/store/...-source/home/zshrc` (re-run on Nix 2.33.0: same). Source: home-manager `modules/files.nix:170-176` (`ln -s` to `toString path`); issues #2085, #2660, #9052 |
| home-manager does not check that a link target exists and prints no warning for a dangling one | Holds | Source: home-manager `modules/files.nix:580,674` (plain `ln -s "$source" "$target"`); its only `warnEcho` (`:395`) is about deleting a link outside a generation |
| `nix flake check` neither evaluates nor builds `darwinConfigurations` / `homeConfigurations` | Holds | Measured: outputs set to `throw` passed with `all checks passed!` and exit 0; a `nixosConfigurations` control failed with exit 1 (re-run on Nix 2.33.0: same). Source: NixOS/nix `src/nix/flake.cc` ("Known but unchecked community attribute") |
| A GitHub-hosted macOS runner can build and switch a darwin system | Holds | Source: nix-darwin `.github/workflows/test.yml` (`runs-on: macos-15`, `sudo nix run .#darwin-rebuild -- switch`, with upstream Nix) |
| nix-darwin's homebrew module does not install Homebrew; without it, activation aborts | Holds | Source: nix-darwin `modules/homebrew.nix:671` ("does not install Homebrew"); `modules/system/checks.nix:247-257` ("requires homebrew installed, aborting activation", `exit 2`). The "skipping" branch runs only while nix-homebrew is installing Homebrew |
| nix-homebrew refuses an existing Homebrew unless `autoMigrate = true`, which replaces the installation and keeps packages | Holds | Source: zhaofengli/nix-homebrew `modules/default.nix:220-226` and its option description |
| Pure evaluation cannot read absolute paths outside the flake, such as `~/.config` | Holds | Measured: `nix eval --pure-eval --expr 'builtins.readDir "<home>/.config"'` failed with "access to absolute path ... is forbidden in pure evaluation mode" (re-run on Nix 2.33.0: same) |
| `writeShellApplication` appends the caller's PATH unless `inheritPath = false`, and runs shellcheck by default | Holds | Source: nixpkgs `pkgs/build-support/trivial-builders/default.nix:286-292` (`bashOptions`, `inheritPath ? true`), `:318-321` (`optionals inheritPath [ "$PATH" ]`) |
| `launchd.user.envVariables` runs `launchctl setenv` as `system.primaryUser` at activation, single-quoted (not expanded) | Holds | Source (by a review agent): nix-darwin `modules/system/launchd.nix:14-15,138-143` |
| `GHQ_ROOT` overrides ghq's root | Holds | Measured: `GHQ_ROOT=/tmp/ghq-root-probe ghq root` printed `/tmp/ghq-root-probe` |
| Claude Code's worktree isolation places worktrees under `.claude/worktrees/` | Holds | Measured: `git worktree list` over every local `paveg` clone found 10 linked worktrees, all under `<repo>/.claude/worktrees/` |
| This Mac runs upstream Nix, not Determinate | Holds | Measured: `nix --version` printed `nix (Nix) 2.33.0`; `/usr/local/bin/determinate-nixd` does not exist |
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
| nixpkgs `fetchurl` with a real hash skips TLS verification; with an empty or fake hash or a netrc it uses nixpkgs' cacert | Holds | Source: nixpkgs `pkgs/build-support/fetchurl/default.nix:338-350` (`SSL_CERT_FILE` is cacert's bundle only for `""` / fake hashes / `netrcPhase`, else `/no-cert-file.crt`), `builder.sh` (`--insecure` when that file is missing). `pkgs/build-support/node/prefetch-npm-deps/default.nix:319-328` uses the same rule |
| `fetchgit` and Go / cargo / npm fetchers take `NIX_SSL_CERT_FILE` from the daemon environment | Holds | Source: nixpkgs `lib/fetchers.nix` (`proxyImpureEnvVars`), `fetchgit/nix-prefetch-git` |
| The Linux sandbox exposes `ssl-cert-file` only at `/etc/ssl/certs/ca-certificates.crt` | Holds | Source: nix `linux-derivation-builder.cc` |
| Some fixed-output derivations hard-code nixpkgs' cacert | Holds | Source: nixpkgs `fetch-yarn-deps`, `build-bazel-package`, `docker`, `fetchrepoproject` |
| `git+https://` inputs and `builtins.fetchGit` run the `git` binary | Holds | Source: nix tag 2.33.0 `src/libfetchers/git-utils.cc:602` (`runProgram` with `.program = "git"`) |
| `hg+https://` passes no CA to `hg`; git LFS uses Nix's own transfer | Holds | Source: nix `mercurial.cc`, `git-lfs-fetch.cc` |
| On Linux, Nix defaults `ssl-cert-file` to `/etc/ssl/certs/ca-certificates.crt`, and the daemon unit sets no `NIX_SSL_CERT_FILE` | Holds (not run on WSL2) | Source: nix `globals.cc` (`getDefaultSSLCertFile`), `misc/systemd/nix-daemon.service.in` |

## 1Password

| Statement | Result | Evidence |
|---|---|---|
| SSH key approvals are by default per key and per application, and last until 1Password locks or quits or for a set time | Holds | Source: 1password.dev, SSH agent security ("Per key, per application (default)"; "until 1Password locks or quits, or until a set amount of time has passed"). Per-terminal-session is a separate, non-default option |
| Only an approval given for a set time survives a lock; then only unlocking is asked again | Holds | Source: same page ("If you've already authorized the client to use your key for a set amount of time (for example, four hours) instead of when 1Password locks, your approval will still be in the agent's memory and you'll only be prompted to unlock 1Password") |
| `agent.toml` selects and orders offered keys; the default offers every key in Personal, Private, or Employee vaults | Holds | Source: 1password.dev, SSH agent config file |
| WSL2 forwards SSH to Windows `ssh.exe`, and commit signing works from WSL2 | Holds | Source: 1password.dev, WSL integration |
| The Linux-side `op` in WSL2 cannot use the desktop app integration | Holds | Source: 1password.dev, CLI app integration |

## Keeper

| Statement | Result | Evidence |
|---|---|---|
| `ksm exec` replaces `keeper://` environment values for a command | Holds | Source: docs.keeper.io, Secrets Manager CLI, exec command |
| `ksm interpolate` renders templates and writes output with mode 0600 | Holds | Source: docs.keeper.io, interpolate command |
| `ksm secret download` / `upload` handle record attachments | Holds | Source: docs.keeper.io, secret command |
| With keyring support, the KSM CLI stores its config in the macOS Keychain | Holds | Source: docs.keeper.io, Secrets Manager CLI ("requires the optional `keyring` extra"; "Without it, profiles fall back to `keeper.ini`") |
| The KSM CLI is not in nixpkgs | Holds | Measured (by a review agent, 2026-11-25): no nixpkgs attribute at nixos-unstable `2786a2a`, top-level or in `python3Packages`, is the Keeper Secrets Manager CLI |

## GitHub tokens (ghtkn, aqua)

| Statement | Result | Evidence |
|---|---|---|
| `ghtkn exec -e <env>[:<app>]` sets a token variable; ghtkn exits 111 without running the command when no token is available; `ghtkn agent unlock --enable-refresh` exists | Holds | Source: suzuki-shunsuke/ghtkn `USAGE.md` at v0.4.3 |
| ghtkn reads `${XDG_CONFIG_HOME:-$HOME/.config}/ghtkn/ghtkn.yaml`; its default backend is the OS keyring; `exec` never starts the device flow | Holds | Source: ghtkn README and `USAGE.md` (main) |
| `git-credential` picks the app from `git_owners`, then `GHTKN_GIT_APP`, then `GHTKN_APP`, then the first app | Holds | Source: ghtkn `USAGE.md` (git credential helper) |
| With the agent backend, the data key is created on the first `ghtkn agent unlock`, and no access token can be obtained until the agent is unlocked; `ghtkn auth` caches the token it gets | Holds | Source: ghtkn `docs/backend.md` (lines 77, 87) and `docs/token-management.md` (line 75), read with `gh api repos/suzuki-shunsuke/ghtkn/contents/docs/...`. That `ghtkn auth` fails against a locked agent is inferred, not run |
| `ghtkn` 0.4.3 and `_1password-cli` (unfree) are in nixpkgs | Holds | Measured (by a review agent): `nix eval` at nixos-unstable `2786a2a` |
| aqua uses ghtkn with `AQUA_GHTKN_ENABLED=true` (aqua v2.54.0 or later); an environment token, or the keyring when `AQUA_KEYRING_ENABLED=true`, takes precedence | Holds | Source: aquaproj.github.io, security / ghtkn; aqua `pkg/github/github.go` (v2.66.1) |

## Commit signing on GitHub

| Statement | Result | Evidence |
|---|---|---|
| With "require signed commits", unsigned commits on a pull request's head branch can block a squash merge, even though GitHub would sign the final squash commit | Holds | Source: github/docs `data/reusables/repositories/required-signed-commits.md` ("unsigned commits on the head branch can block a squash merge, even though GitHub would sign the final squash commit") |

## Orca

| Statement | Result | Evidence |
|---|---|---|
| Orca merges 16 hook entries into `~/.claude/settings.json`, keeping other keys, at app start and when its hook setting changes; it backs up the old file to `settings.json.bak` | Holds | Measured: 16 entries whose command matches `agent-hooks/claude-hook` (`jq` over the file); `settings.json.bak` written at the last Orca launch. Source (by a review agent): Orca 1.4.273 `app.asar`, `out/main/index.js` (startup reconcile) and `hook-service` chunk (strip own entries, append, keep other keys) |
| Orca's Claude hook lets Orca decide `PreToolUse` and `PermissionRequest` | Holds | Source: `~/.orca/agent-hooks/claude-hook.sh:18-19` (`orca_hook_decides=claude-pre-tool-use-v1`, `claude-permission-request-v1`, up to 126 s) |
| A remote Orca server (`orca serve`) can be a headless Linux host, must stay awake and on the same tailnet or LAN, and pairs with the mobile app; closing the desktop app drops a direct/LAN session | Holds | Source (by a review agent): orca.dev/docs/remote-servers ("a headless Linux server or a service-managed VM"; "the server must stay awake and connected to the tailnet"); orca.dev/docs/mobile ("Closing the desktop app drops a direct/LAN session until you reopen it") |
| 1Password for Mac has "Lock when device locks or sleeps"; a locked 1Password prompts on the Mac when a key is used; Apple Watch unlock needs the watch close to the Mac | Holds (default not documented) | Source (by a review agent): support.1password.com/unlock-auto-lock; 1password.dev/ssh/agent/security; support.apple.com/102442 |
| 1Password service accounts work headless through `OP_SERVICE_ACCOUNT_TOKEN` and cannot access Personal, Private, Employee, or the default Shared vault | Holds | Source (by a review agent): 1password.dev/service-accounts/use-with-1password-cli, /service-accounts/get-started |
| Commits made through GitHub's REST API as a GitHub App, with no custom author, committer, or signature, are signed by GitHub | Holds | Source (by a review agent): docs.github.com, about commit signature verification |
| GraphQL `createCommitOnBranch` commits are authored by "the owner of the credential which authenticates the API request" and "automatically signed by GitHub if supported", with no App or bot condition | Holds | Source: `createCommitOnBranch` description read from GitHub's live GraphQL schema (`gh api graphql` introspection). Not run with a user token |
| Secretive can create a Secure Enclave key whose use needs no authentication, and such keys cannot be exported | Holds | Source (by a review agent): maxgoedjen/secretive v4.0.0 `CreationOptions.swift` (`case notRequired`, "Authentication is not required for usage."); README ("it's impossible to export them, by design") |
| A 1Password CLI desktop-integration authorization is per TTY and expires after 10 minutes of inactivity, 12 hours at most | Holds | Source (by a review agent): 1password.dev/cli/app-integration-security ("Authorization expires after 10 minutes of inactivity"; "hard limit of 12 hours"; "based on the current `tty`") |
| The Orca iOS app is a thin client; terminals and agents run on the paired desktop or a remote Orca server | Holds | Source: App Store listing "Orca IDE" ("Nothing runs on your phone except the viewer"); orca.dev/docs/mobile ("The paired desktop owns the agent sessions") |

## Claude Code guardrails

| Statement | Result | Evidence |
|---|---|---|
| Bash permission patterns are not a security boundary; `bash -c` is not unwrapped | Holds | Source: code.claude.com/docs/en/permissions ("isn't a security boundary around the program") |
| A PreToolUse hook that exits with another code, cannot start, times out, or prints invalid output lets the call proceed, unless `onFailure: "block"` is set | Holds | Source: code.claude.com/docs/en/hooks, "Block the action when a hook fails" (`"continue"` / `"block"`, v2.1.295 or later, no effect on `async` hooks). Installed Claude Code is 2.1.331 |
| Plain stdout with exit 0 is not a hook failure, so `onFailure` does not block it | Holds | Source: code.claude.com/docs/en/hooks ("Plain-text stdout from a command hook isn't a failure") |
| On macOS an unset `sandbox.network.allowUnixSockets` blocks every Unix socket; Linux and WSL2 ignore the list and use `allowAllUnixSockets` | Holds | Source: code.claude.com/docs/en/settings, `sandbox.network.allowUnixSockets` ("Default: unset, so the macOS sandbox blocks every Unix socket") |
| By default Claude Code runs commands unsandboxed when the sandbox cannot start, unless `sandbox.failIfUnavailable: true` | Holds | Source: code.claude.com/docs/en/sandboxing |
| Installing a plugin at user scope writes `enabledPlugins` in `~/.claude/settings.json`; if the file is generated or read-only, the change lasts only for the session | Holds | Source: code.claude.com/docs/en/plugins (install scope); /settings ("A change you made in Claude Code is lost in new sessions") |
| Codex reads global instructions from `~/.codex/AGENTS.override.md` or `~/.codex/AGENTS.md`, not `~/.claude/CLAUDE.md` | Holds | Source: Codex docs, AGENTS.md ("In your Codex home directory ... Codex reads `AGENTS.override.md` if it exists. Otherwise, Codex reads `AGENTS.md`"). Measured: `~/.codex/AGENTS.md` and `~/.claude/CLAUDE.md` are separate regular files, and `config.toml` sets no fallback |
| Codex writes `config.toml` at run time (project trust levels), resolving symlinks and writing atomically | Holds | Source: openai/codex `codex-rs/core/src/config/edit.rs` (`resolve_symlink_write_paths`, `write_atomically`) |
| Codex has hooks (`hooks.json` or `[hooks]` in `config.toml`, including `PreToolUse`) | Holds | Source: Codex docs, hooks. Measured: `~/.codex/config.toml` sets `hooks = true` |
| `errexit` is suspended inside conditions: a failing command in a function called from `if` falls through | Holds | Measured: `bash -c 'set -o errexit -o nounset -o pipefail; guard(){ false; echo reached-after-false; }; if guard; then echo exit0-path; fi; echo rc=$?'` printed `reached-after-false`, `exit0-path`, `rc=0` |
| `errexit` is also suspended inside `$(…)` unless `shopt -s inherit_errexit` is set | Holds | Measured on bash 3.2.57 (`/bin/bash`) and 5.3.20 (nixpkgs): with `classify(){ false; echo safe; }; v=$(classify)`, the script continued with `v=safe`; on 5.3 with `shopt -s inherit_errexit` it exited 1 before printing. bash 3.2 has no `inherit_errexit` |
| With `inherit_errexit`, a guard whose classification runs in `$(…)` aborts (rc 1, so `onFailure` blocks) when a command fails midway; without it, the classification carries on | Holds | Measured on bash 5.3.20 with a prototype guard: match printed `deny` (rc 0), no match printed nothing (rc 0), a failure midway gave rc 1. With the `inherit_errexit` line removed, a failure midway gave rc 0 with no output on a non-matching input |
| A matcher that errors inside `if` reads as "no match" | Holds | Measured on bash 5.3.20: a prototype variant using `if … \| grep -q` with the pattern `DANGER(`, which grep rejects, gave rc 0 and no output on a matching input; with a valid pattern it printed `deny` |
| A hook's `allow` decision skips the permission prompt; exit 0 with no output goes through the normal permission flow | Holds | Source (by a review agent): code.claude.com/docs/en/hooks ("`"allow"` skips the permission prompt"; "staying silent doesn't approve it"; precedence `deny > defer > ask > allow`) |
| The previous credential and database guards fail open when `jq` is not on PATH | Holds | Measured: with `env -i PATH=<empty dir>`, the credential guard exited 0 with no output and the database guard exited 127; with a normal PATH both returned `permissionDecision: "deny"` (re-run 2026-11-25: same) |
| The previous setup registered eight hooks of its own (six `jq`-based bash scripts, one Python script, one `type: "agent"` Stop hook), plus one herdr-managed hook | Holds | Measured: `jq` over `~/.claude/settings.json` lists `block-credential-read`, `block-destructive-db`, `block-unsigned-commits`, `gh-pr-inject`, `browser-inject`, `japanese-writing-inject` (`.sh`, each uses `jq`), `block-rot-comments.py`, an agent-type Stop hook ("Checking for unaddressed requests"), and `herdr-agent-state.sh`, whose header reads "installed by herdr; managed by herdr" and which does not use `jq` |
| The sandbox covers shell commands only; file tools, MCP servers, and hooks run outside it | Holds | Source: code.claude.com/docs/en/sandboxing |
| The sandbox can deny reads (`filesystem.denyRead`), restrict network by domain, and refuse unsandboxed retries (`allowUnsandboxedCommands: false`), on macOS and WSL2 | Holds | Source: code.claude.com/docs/en/sandboxing |
| `Read(...)` deny rules cover file tools and recognized Bash file commands (`cat`, `head`, `tail`, `sed`, `tee`, redirections) | Holds | Source: code.claude.com/docs/en/permissions |

## Hook need across repositories

Collected 2026-11-25. Repositories: `gh repo list paveg` returned 131, of which 70 are neither archived nor forks; each of the 70 file trees was read through the GitHub API (no errors). Past sessions: 693 transcripts under `~/.claude/projects`, excluding the session that wrote this table. Deny counts are transcript lines carrying the hook's deny text, so they are a rough order of magnitude, not exact firings.

| Hook | Repository signal | Past sessions | Verdict |
|---|---|---|---|
| Destructive-database guard | 14 repositories with a drizzle config or SQL migrations (names omitted: most are private) | 5 deny lines in 3 projects | Needed |
| Credential-read guard | Every repository (any can hold a secret) | 59 deny lines in 10 projects | Needed until the sandbox's `denyRead` replaces it |
| Unsigned-commit guard | — | 2 deny lines in 1 project | Replaced by deny rules and GitHub's rule |
| Comment-rot check | Every code repository | 13 deny lines in 6 projects | Needed |
| PR-body context | Every repository with pull requests | 148 injections | Needed |
| Japanese-writing context | Repositories with Japanese Markdown | 450 injections (Edit and Write) | Needed |
| Browser context | Not repository-bound (Chrome MCP) | about 1,300 injections of a 43-word rule | Needed; cheap per call |
| Unaddressed-request check | Every repository | 52 "condition was not met" lines in 11 projects | Needed |
| Repository-level hooks | 5 repositories have `.claude/settings.json`; only one defines a hook (`UserPromptSubmit`, project-specific) | — | Stay in their repositories |

Injection counts are `hook_additional_context` attachments grouped by hook event and the opening text of the injected context.

## Other tools

| Statement | Result | Evidence |
|---|---|---|
| apm (microsoft/apm) is pre-1.0, supports Claude Code user scope, and is in nixpkgs | Holds | Source: microsoft/apm releases (v0.38.1), `docs/.../reference/targets-matrix.md`; nixpkgs `pkgs/by-name/ap/apm-cli/package.nix` |
| `orca serve` accepts clients from localhost, LAN, and Tailscale (100.64/10, fd7a:115c:a1e0::/48) addresses; public addresses only with `--allow-public` or listed conditions | Holds | Measured: `orca serve --help` (installed Orca CLI) |
| On a packaged macOS app, `orca serve` runs Electron, which needs a desktop login; `ORCA_SERVE_RUNTIME=orcad` runs a Node server without one | Holds | Measured: `orca serve --help` |
| `orca serve service install` writes a LaunchAgent on macOS (a systemd user unit on Linux) | Holds | Source (by a review agent): orca.dev/docs/remote-servers; subcommands `install`, `status`, `uninstall` present in the installed CLI |
| FileVault is active on this Mac | Holds | Measured: `fdesetup isactive` printed `true` |
| nix-darwin has `services.tailscale` and `power.sleep.computer` (accepts `"never"`) | Holds | Source (by a review agent): nix-darwin `modules/services/tailscale.nix`, `modules/power/sleep.nix` |
| Tailscale's default key expiry is 180 days and can be disabled per device; Tailscale SSH's server needs the open-source `tailscaled` on macOS; the free plan covers this use | Holds | Source (by a review agent): tailscale.com/kb/1028/key-expiry, tailscale.com/kb/1193/tailscale-ssh, tailscale.com/pricing |
| `update-flake-lock` pull requests opened with the default token do not trigger CI; a token with Contents and Pull requests write access does | Holds | Source (by a review agent): github.com/DeterminateSystems/update-flake-lock README |
| `orca serve service status` prints "… is not installed" and exits 0 when no service exists | Holds | Measured on this Mac |
| The LaunchAgent written by `orca serve service install` runs `orca serve --supervise --no-pairing` and stores the installing shell's PATH | Holds | Measured: `orca serve service install --dry-run` |
| `orca pair --mobile --address <host>` makes the phone dial that address, for example a Tailscale one | Holds | Measured: `orca pair --help` |
| Homebrew's core `orca` cask is plotly's Orca, disabled; Orca the IDE ships its own tap, `stablyai/orca`, with `Casks/orca.rb` (version 1.4.274, depends on macOS Ventura) | Holds | Measured: `brew info --cask orca`, `brew search --cask orca`; `gh api repos/stablyai/homebrew-orca/contents/Casks/orca.rb`; Orca's install docs (by a fetch agent) |
| This Mac's `/usr/local/bin/tailscale` wraps the Tailscale GUI app | Holds | Measured: the wrapper runs `/Applications/Tailscale.app/Contents/MacOS/Tailscale` |
| atuin's `secrets_filter` defaults to `true`; its patterns include GitHub PATs, `ghu_`, `ghs_`, GitHub refresh tokens, AWS key IDs, Slack, and Stripe | Holds | Source: atuin main, `crates/atuin-client/config.toml` (`# secrets_filter = true`) and `crates/atuin-common/src/secrets.rs` (pattern names), read with `gh api`. Same defaults in v18.24.8, the nixpkgs version (by a review agent) |
| atuin's `auto_sync` defaults to `true`, with `https://api.atuin.sh` as `sync_address`; `history_filter` and `cwd_filter` take regular expressions | Holds | Source: atuin main, `crates/atuin-client/config.toml` |
| `k9s` and `stern` are nixpkgs attributes | Holds | Measured: `nix eval --raw nixpkgs#k9s.name` printed `k9s-0.51.0`, `nixpkgs#stern.name` printed `stern-1.35.0` (upstream Nix 2.33.0 on this Mac, registry `nixpkgs`) |
| nixpkgs has `tlaplus18` (tlaplus-1.8.0), `tlaplus` (1.7.4), `lean4` (4.35.0), and `elan` (4.3.0) | Holds | Measured: `nix eval --raw nixpkgs#<attr>.name` on this Mac |
| `tlaplus18` installs `tlc`, `tlasany`, `pcal`, `tlatex`, and `tlarepl` as wrappers around `tla2tools.jar` | Holds | Source: nixpkgs `pkgs/by-name/tl/tlaplus18/package.nix` (`makeWrapper … $out/bin/<name>`), read with `gh api` |
| `actions/create-github-app-token` scopes the token to the current repository when `owner` and `repositories` are empty, and the token inherits all of the installation's permissions | Holds | Source (by a review agent): actions/create-github-app-token README |
| `nix develop -c <cmd>` runs the devShell's `shellHook` | Holds | Measured (by a review agent) on upstream Nix 2.33.0 with a minimal flake: the hook's marker and exported variable appeared in the command's output |
| elan reads `ELAN_HOME` and defaults to `~/.elan`; nixpkgs' elan patches downloaded toolchains on Linux only | Holds | Source (by a review agent): leanprover/elan `src/elan-utils/src/utils.rs`; nixpkgs `pkgs/by-name/el/elan/package.nix` |
| `tlc <Module>.tla` reads `<Module>.cfg` beside it; a model that reaches a final state fails with "Deadlock reached" unless deadlock checking is off or the final state stutters | Holds | Measured (by a review agent) with nixpkgs `tlaplus18` |
| A pull request opened with a GitHub App token triggers `push` and `pull_request` workflows; Contents and Pull requests write suffice unless the change touches workflow files | Holds | Source (by a review agent): peter-evans/create-pull-request `docs/concepts-guidelines.md` |
| A liveness property "a restarted run eventually finishes" fails under weak fairness when a run may stop after any step, and holds with strong fairness on the steps | Holds | Measured: TLC (nixpkgs `tlaplus18`) on a minimal Step/Stop/Restart model reported "Temporal properties were violated" with a Stop/Restart loop under `WF_vars(Step)`, and "No error has been found" under `SF_vars(Step) /\ WF_vars(Restart)`. With `SF_vars(Step)` alone it is violated by a stop that is never restarted (measured by a review agent) |
| Karabiner-Elements reads `~/.config/karabiner/karabiner.json`; link the directory, not the file, or Karabiner fails to detect changes and reload | Holds | Source (by a fetch agent): karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/ |
| Karabiner-Elements needs background services, Accessibility, Input Monitoring, and driver extension approvals after install | Holds | Source (by a fetch agent): karabiner-elements.pqrs.org/docs/getting-started/installation/ |
| Raycast exports settings only as an encrypted `.rayconfig` (passphrase of at least 8 characters); Cloud Sync needs Pro; Script Commands are indexed from directories the user adds | Holds | Source (by a fetch agent): manual.raycast.com/import-export, /cloud-sync, /script-commands |
| Karabiner writes `automatic_backups/` into its config directory, and Raycast's data is SQLite under `~/Library/Application Support/com.raycast.macos/` | Holds | Measured: directory listings on this Mac |
| Under the PATH `/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin`, `orca serve service install --dry-run` exits 1; with `--command /usr/local/bin/orca` it succeeds and the plist runs that path | Holds | Measured on this Mac |
| `orca serve service status --json` reports `"installed": false` when no service exists | Holds | Measured on this Mac |
| `orca pair` mobile pairing works on the same network or tailnet only, unless `--relay` is given | Holds | Source (by a review agent): `orca pair --help` |
| home-manager's `recursive` option defaults to `false`, which links a directory as a single symlink | Holds | Source (by a review agent): home-manager `modules/lib/file-type.nix` |
| After moving Karabiner's config, `launchctl kickstart -k gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server` is needed once for Karabiner to watch the new location | Holds | Source (by a review agent): karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/ |
| Raycast for Windows installs with `winget install raycast` and supports Windows 10 21H2+ and Windows 11; `.rayconfig` files are cross-platform between Mac and Windows; Script Commands on Windows run with the interpreter on the Windows PATH | Holds | Source (by a fetch agent): raycast.com/windows, manual.raycast.com/import-export, manual.raycast.com/script-commands. Release status (beta or GA) and arm64 support are not stated |
| winget has `AgileBits.1Password` (8.12.46.29) and `AgileBits.1Password.CLI` (2.42.0); Raycast has no manifest in the winget community repository | Holds | Measured: `gh api repos/microsoft/winget-pkgs/contents/manifests/a/AgileBits/...` (PackageIdentifier in the latest manifests); the full `manifests/r` tree (416 entries) has no Raycast |
| 1Password forwards SSH from WSL to Windows `ssh.exe` (`git config --global core.sshCommand ssh.exe`); signing uses a snippet from the 1Password app and needs Git 2.34.0+ and 64-bit Windows 10+ (Arm Windows not supported); WSL's `[interop] enabled = true` is required; the integration supports WSL 1 and 2 | Holds | Source (by a fetch agent): 1password.dev/ssh/integrations/wsl/ |
| The Linux `op` inside WSL cannot use the desktop app integration; 1Password recommends calling the Windows `op.exe` from WSL | Holds | Source (by a fetch agent): 1password.dev/cli/app-integration/ |
| WSL's `[interop] enabled` and `appendWindowsPath` both default to `true` | Holds | Source (by a fetch agent): learn.microsoft.com/windows/wsl/wsl-config |
