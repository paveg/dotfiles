# Design: thin dotfiles for the agent era

- Status: Accepted for implementation (items marked **Unverified** must be checked before they are relied on)
- Date: 2026-11-25

This repository replaces a chezmoi + devbox global setup with a new, thin design. It is not a migration: the old repository is a source of ideas, not a constraint. Decisions with lasting consequences are recorded as ADRs in [`adr/`](adr/). Evidence for the factual statements below is in [`verification.md`](verification.md).

## Context

AI coding agents (Claude Code, Codex, agents run in parallel by Orca) now drive the shell for most day-to-day work. That changes what a dotfiles repository is for: it is no longer about tuning a human's muscle memory, but about giving agents an environment where every tool resolves the same way and where humans are interrupted as rarely as possible.

Three properties of the previous setup work against that:

- Agents see the shell inconsistently. An agent that runs plain `zsh -c` never sees aliases, shell functions, or hook-activated environments (direnv, `mise activate`). Claude Code's Bash tool, by contrast, replays a snapshot of the interactive shell, so it does get aliases such as `ls='eza --icons'` and shadowed standard commands. Either way, behaviour depends on which agent runs the command.
- Packages float on `@latest` with no committed lock, so the setup is not reproducible.
- Company connection settings sat in a public repository.

## Goals

1. **Reproducible**: macOS and WSL2 rebuild from locked definitions with one bootstrap run.
2. **Same view for agents**: non-interactive shells, GUI apps, and agents see the same global and project tools.
3. **Few interruptions**: minimize password prompts, approvals, and manual steps.
4. **Secrets stay in vaults**: personal secrets live in 1Password, company secrets and company config in Keeper. Commands receive them at run time. A secret is rendered to a file only when a tool cannot take it any other way; such files are mode 0600, untracked, and listed in the design.
5. **Short-lived GitHub tokens**: `gh` and agents get tokens from ghtkn; no long-lived token is stored.
6. **Work / personal separation by host profile**: packages, git identity, ghtkn apps, and agent skills/plugins switch with the host.
7. **No company information in this repository.**
8. **Works behind the corporate TLS-intercepting proxy.**

## Non-goals

- Rewriting config file contents in the Nix language (no `programs.*` generation).
- Managing the Windows side (`%USERPROFILE%`) of WSL2 hosts.
- Maximum shell start-up speed.
- Human-oriented shortcuts (aliases, functions).
- Exhaustive macOS defaults: start empty, add only what is missed.

## Principles

| # | Principle | Meaning |
|---|---|---|
| P1 | PATH is built in `.zshenv` and holds only real executables | No reliance on aliases, functions, or shell hooks. A wrapper, when needed, is an executable. |
| P2 | Never shadow standard commands | No `ls`/`cat`/`grep`/`find` aliases. Use `eza`/`bat`/`rg` under their own names. |
| P3 | Nix wires, files configure | Nix handles packages, symlinks, and two small generators (merged `settings.json`, the `gh` wrapper). Config content stays in plain files. |
| P4 | Lock files are committed | `flake.lock` is tracked and updated explicitly. |
| P5 | Agent config is a first-class asset | `~/.claude/` and `~/.codex/` are covered by tests and CI. |
| P6 | Two questions before adding anything | Does it reach a process without an interactive shell? Does it remove a human interruption? If neither, leave it out. |
| P7 | Secrets come from a vault | Secret values never live in this repository. `op://` references for the personal profile may (they are pointers that need the account to resolve). Anything identifying the company, including `keeper://` references and org names, lives only in the work profile. gitleaks guards against leaks. |

## Hosts

| Host | OS | Stack |
|---|---|---|
| `personal-mac` | macOS arm64 | Determinate Nix + nix-darwin + home-manager (darwin module) |
| `work-mac` | macOS arm64 | Same, with the work profile |
| `wsl` | WSL2 Ubuntu | Determinate Nix (requires systemd) + standalone home-manager |

Host names are placeholders. WSL2 also uses Determinate Nix: installing upstream Nix through the Determinate installer needs `--prefer-upstream-nix`, which the installer README calls unsupported and possibly removed in a future release. See [ADR 0001](adr/0001-nix-stack.md).

## Architecture

| Layer | Owner | Responsibility |
|---|---|---|
| Nix | Determinate Nix | Install and update Nix; import Keychain CAs on macOS |
| System (macOS) | nix-darwin + nix-homebrew | Casks (nix-darwin's homebrew module does not install Homebrew itself, so nix-homebrew does), launchd agents |
| User (all hosts) | home-manager | `home.packages`, symlinks, generated `settings.json` |
| Config files | Plain files in `home/` | zsh, git, nvim, ghostty, Claude Code, Codex |
| Work profile | Files fetched from Keeper into `~/.config/dots-work/` (untracked) | Internal endpoints, internal plugin marketplaces, ghtkn work apps, work git identity |
| Project | One default tool per project (see below) | Language runtimes and project tools |

### Nix layer

- nix-darwin sets `nix.enable = false`; Determinate manages Nix. nix-darwin aborts activation when it detects Determinate with `nix.enable` on. With Determinate's nix-darwin module, this is set automatically and Nix settings go in `determinateNix.customSettings`.
- Cost: nix-darwin's `nix.*` options and its Linux builder are unavailable.

### home-manager symlinks

- `mkOutOfStoreSymlink` takes the checkout's **absolute path as a string**. Passing a flake-relative path such as `./home/.zshrc` copies the file into the store, so edits do not show up.
- With absolute paths, edits to existing files apply immediately. Adding, removing, or renaming a linked file needs a switch.

### Project layer

- No language runtimes are installed globally.
- The default for new projects is **mise in shims mode** ([ADR 0006](adr/0006-project-layer-mise-shims.md)). The condition it meets: its tools resolve from `zsh -c` without a shell hook. `.zshenv` puts `~/.local/share/mise/shims` on PATH, and nothing calls `mise activate`. Measured: with only the shims directory on PATH, a non-interactive `zsh -c` ran a project tool declared in `mise.toml`.
- Hook-activated environments (direnv, `mise activate`) are not used, because a plain `zsh -c` never sees them.
- Existing projects keep what they use (devbox, a flake devShell). Agents then run commands through `devbox run` / `nix develop -c`, which the project's own CLAUDE.md states.
- Repositories that pin tools in `.aqua.yaml` use aqua, whose bin directory `.zshenv` also puts on PATH.

### Rejected

| Candidate | Reason |
|---|---|
| chezmoi | Overlaps with home-manager's file placement. |
| devbox global | Cannot manage casks; no clear lock. |
| home-manager `programs.*` | Generated config is hard for agents to read. Exception: shell integration that has no other form. |
| Direct `brew install` | Casks only through nix-darwin. |
| zinit, powerlevel10k, starship | Agents never see the prompt. Plain zsh prompt. |
| A business-mode environment variable | Replaced by host profiles. |
| Auto-starting tmux on SSH | Gets in the way of agents connecting over SSH. |
| `gh` as a shell function | Invisible to non-interactive shells. It becomes an executable wrapper. |
| Plain-text `~/.env.local` with secrets | Secrets come from a vault. |
| A private git repository for company config | Puts company information on a personal GitHub account. Keeper, which the company provides, holds it instead. See [ADR 0002](adr/0002-secrets-and-work-profile.md). |
| apm (Agent Package Manager) | Pre-1.0, and key preconditions (several user-scope manifests) are unverified. Revisit if third-party plugins grow enough to need version pinning. |

## Repository layout

Repositories live at `~/src/github.com/<owner>/<repo>`.

```
.
├── flake.nix                 # inputs and host wiring only
├── flake.lock
├── hosts/{personal-mac,work-mac,wsl}.nix
├── nix/
│   ├── darwin.nix
│   ├── home.nix              # packages, symlinks
│   ├── packages.nix
│   ├── agents.nix            # ~/.claude and ~/.codex wiring
│   └── secrets.nix           # 1Password, Keeper, ghtkn wiring
├── home/
│   ├── .zshenv
│   ├── .zshrc
│   ├── .config/git/{config,ignore,personal.gitconfig}
│   ├── .config/{nvim,ghostty}/
│   ├── .ssh/config
│   ├── .claude/
│   ├── .codex/
│   └── .local/bin/
├── profiles/work.example/    # shape of the work profile, empty values, used by CI
├── tests/
├── scripts/{bootstrap.sh,ca-bundle.sh,work-sync.sh}
├── docs/
├── .github/workflows/
├── CLAUDE.md
└── README.md
```

The work profile lives only on `work-mac`, untracked:

```
~/.config/dots-work/
├── claude/settings.work.json   # internal API endpoint, internal marketplaces, work plugins
├── claude/mcp.work.json        # internal MCP servers
├── claude/skills/<name>/       # work-only skills that must not be public
├── git/include.gitconfig       # the includeIf for the work org directory (keeps the org name out of this repository)
├── git/work.gitconfig          # work identity, ghtkn credential helper, http.sslCAInfo
├── ghtkn/{ghtkn.yaml,gh-app}
├── env/static.env              # non-secret variables every shell needs (e.g. AQUA_GHTKN_ENABLED, GHTKN_APP); sourced by .zshenv
└── env/work.env                # keeper:// references only, for ksm exec
```

- The canonical copy is stored as attachments on a Keeper record. `scripts/work-sync.sh` pulls with `ksm secret download` and pushes with `ksm secret upload`.
- This repository links to it with absolute-path `mkOutOfStoreSymlink`. If the directory is missing, the links dangle, the switch still succeeds, and activation prints a warning. Every consumer tolerates the missing profile: git silently ignores a missing include file (measured), `.zshenv` sources `static.env` only if it exists, and the `settings.json` merge falls back to the common file alone.

## Detailed design

### Shell

- `.zshenv` (every shell): PATH (Nix profiles, `~/.local/bin`, mise shims, aqua's bin directory), `EDITOR`, `XDG_*`, and `~/.config/dots-work/env/static.env` if it exists. No secrets.
- `.zshrc` (interactive only): completion, history, key bindings (`Ctrl+g` for ghq + fzf, `Ctrl+r` for fzf history), plain prompt. Sources `~/.zshrc.local` (untracked, non-secret local settings) if present.
- Aliases: none by default. At most short forms that shadow nothing, such as `g=git`.

### GUI apps and PATH

| How the app runs commands | PATH it sees |
|---|---|
| Starts zsh (opens a terminal, probes PATH with `zsh -ic`) | Whatever nix-darwin's `/etc/zshenv` and `~/.zshenv` set. Nothing extra needed. |
| Executes binaries without a shell | launchd's default, `/usr/bin:/bin:/usr/sbin:/sbin` |

- With `useUserPackages = true`, packages land in `/etc/profiles/per-user/$USER/bin`, but only shell initialization adds that directory to PATH.
- Only if an app turns out to run binaries without a shell: use `launchd.user.envVariables.PATH` (nix-darwin runs `launchctl setenv` for the primary user at switch time; the value is not expanded, so write absolute paths), or `sudo launchctl config user path` (applies to all users, needs a reboot).
- Whether Orca starts zsh is checked by an acceptance criterion.

### Git

```gitconfig
# home/.config/git/config (excerpt)
[ghq]
  root = ~/src
[core]
  excludesFile = ~/.config/git/ignore
[include]
  path = ~/.config/git/personal.gitconfig
[include]
  path = ~/.config/dots-work/git/include.gitconfig   # absent on personal hosts; git ignores it
```

```gitconfig
# ~/.config/dots-work/git/include.gitconfig (work profile, not in this repository)
[includeIf "gitdir:~/src/github.com/<work-gh-org>/"]
  path = ~/.config/dots-work/git/work.gitconfig
```

- Identity switches per directory with `includeIf`. Linked worktrees created from a work repository also get the work identity (measured).
- The `includeIf` names the GitHub org directory, so it lives in the work profile, not here.
- Worktrees live in each repository's `.worktrees/<branch>`; the global ignore lists `.worktrees/`.

### Agent configuration

See [ADR 0003](adr/0003-agent-config-profiles.md).

**Wiring.** `~/.claude` also holds runtime state written by Claude Code (`projects/`, `history.jsonl`, `sessions/`, `plugins/`, `.credentials.json`, and more). Link individual entries, never the whole directory.

| Entry | Wiring |
|---|---|
| `CLAUDE.md`, `rules/`, `hooks/`, `agents/`, `references/`, `statusline.sh` | Symlink into this repository |
| `skills/<name>` | Symlinked per profile (below) |
| `settings.json`, MCP config | Generated by merging common and profile JSON (below) |
| Everything else | Not managed |

Codex (`~/.codex/`) follows the same rules. Whether Codex writes back to `config.toml` is **Unverified**; if it does, treat it like `settings.json`.

**Skills per profile.**

```
home/.claude/skills/{common,personal,work}/<name>/
~/.config/dots-work/claude/skills/<name>/      # work-only, not public
```

`nix/agents.nix` lists `common` plus the host's profile with `builtins.readDir` and links each skill flat into `~/.claude/skills/<name>`. There is no exclusion list. A name present in two profiles is an evaluation error.

Pure evaluation cannot read `~/.config/dots-work/` (absolute paths outside the flake are forbidden, measured), so work-profile skills are linked by an activation script instead. That script also fails on a name that already exists in `~/.claude/skills/`.

**Generated `settings.json`.**

- Activation deep-merges `settings.common.json` with the profile's JSON (`settings.personal.json` in this repository, or `~/.config/dots-work/claude/settings.work.json`) using jq, and writes `~/.claude/settings.json` as a regular file. If the work file is missing, the common file is used alone and activation warns.
- Not a store symlink: Claude Code may write to `settings.json` (for example from `/plugin`), and a read-only file could make that fail (**Unverified**).
- Changes made inside Claude Code are overwritten by the next switch. The switch prints the diff between the generated file and the current one first.
- The merge concatenates and de-duplicates arrays instead of using jq's plain `*`, which replaces them. Profiles need their own array entries: the work profile adds `permissions.deny` rules (cloud, cluster, and infrastructure CLIs) that must not apply to personal hosts.

**Environment facts for agents.** `~/.claude/CLAUDE.md` (also read by Codex) states:

- where repositories live (`~/src/github.com/<owner>/<repo>`);
- global tools are added to `nix/packages.nix`, never with brew or `npm -g`;
- project tools come from the project layer's default;
- GitHub tokens come from ghtkn: never run `gh auth login` or export a token.

**Guardrails.** See [ADR 0007](adr/0007-agent-guardrails.md). Protection is split into three layers: the sandbox enforces Bash reads, writes, and network (enabled only after measurement, below); `permissions.deny` covers Claude's file tools and common Bash forms (for example `Read(~/.aws/**)`); hooks are tripwires for judgements the other two cannot express. Claude Code's docs state that hooks and Bash patterns are not a security boundary, and that a PreToolUse hook that fails for any reason lets the call proceed unless it sets `onFailure: "block"`.

| Hook | Kind | On failure |
|---|---|---|
| Destructive-database guard | Guard | Block (`onFailure: "block"`, and `deny` on malformed input) |
| Comment-rot guard | Guard | Block |
| PR, browser, and Japanese-writing context injectors | Injector | Proceed |

- Every hook is built with `writeShellApplication`: `runtimeInputs` pins `jq`, coreutils, and grep, so nothing is resolved from the caller's PATH, and shellcheck runs at build time. The generated `settings.json` refers to hooks by store path.
- The credential-read and unsigned-commit guards from the previous setup are replaced by `Read(...)` deny rules plus sandbox `denyRead`, and by a `--no-gpg-sign` deny rule plus GitHub's "require signed commits".
- `Edit` deny rules on `~/.claude/hooks/**` and `~/.claude/settings.json` stop the agent from editing its own guards by accident. They do not stop a hostile agent.
- Sandbox: before enabling it with `allowUnsandboxedCommands: false`, measure on each host that the 1Password SSH agent socket, the ghtkn agent, the Nix daemon socket, and `op` / `ksm` still work (`allowUnixSockets` defaults on macOS are **Unverified**).
- Upgrade condition: if a concrete bypass of the database guard needs closing (for example through `bash -c`), rebuild that guard as a Go binary that parses commands into a syntax tree.

**Safe updates.** Hooks, skills, and scripts ship with tests that run in CI. Each guard's test is shown to fail when the guard is deliberately broken. CI also generates `settings.json` and checks that it is valid JSON and contains the required hooks, using `profiles/work.example/` for the work side.

### Secrets

See [ADR 0002](adr/0002-secrets-and-work-profile.md).

| Use | Personal | Work |
|---|---|---|
| Token for one command | `op run --env-file=...` with `op://` references | `ksm exec -- <cmd>` with `keeper://` references |
| Token inside a config file | `op inject` | `ksm interpolate -o <file>` (written with mode 0600) |
| MCP tokens | MCP config holds `${VAR}` only; the value comes from the row above | Same |
| Work profile files | — | Keeper record attachments |
| SSH keys, commit signing | 1Password | 1Password (work repositories use HTTPS + ghtkn for transport) |
| GitHub tokens | ghtkn | ghtkn |

- Shell start-up exports no secrets; only the command that needs one gets it.
- Prefer the run-time forms (`op run`, `ksm exec`). Rendered files (`op inject`, `ksm interpolate`) are written only for tools that cannot read a secret from the environment. They are mode 0600, untracked, and listed in the design. Today the only one is the personal `ghtkn.yaml`, which holds client IDs rather than secrets.
- Besides rendered files, the only credentials on disk are the 1Password and Keeper Secrets Manager device configs. Installed with keyring support, the KSM CLI stores its config in the macOS Keychain.
- gitleaks runs as a pre-commit hook and in CI.
- Prerequisite: whether Keeper Secrets Manager needs admin enablement or an extra license is not covered by Keeper's docs; ask company IT. If it is unavailable, the work profile stays local to `work-mac` and is recreated by hand on a new machine.

### 1Password agent and prompts

1Password raises two kinds of prompts.

| Prompt | When | How to reduce it |
|---|---|---|
| Unlock | 1Password is locked | Unlock with Touch ID (Windows Hello on Windows). Set the auto-lock timeout in 1Password. |
| Key approval | By default per key and per application; in terminals, per tab. An approval lasts until 1Password locks or quits. | See below |

- **Approvals survive locking.** Per 1Password's docs, after a lock you are only asked to unlock. With Touch ID, that means no typed password.
- **Offer fewer keys.** `agent.toml` selects which keys the agent offers and in what order. Without it, the agent offers every key in the Personal, Private, or Employee vault and can exceed the common server default `MaxAuthTries` of 6. The personal `agent.toml` is committed under `home/`; work keys, if any, are added from the work profile.
- **Reuse connections.** `ControlMaster auto` / `ControlPersist` in `~/.ssh/config` for github.com should let later connections from the same tab skip the agent, and so the prompt (**Unverified**).
- **No `op` at shell start-up.**
- **Agents use ghtkn tokens for GitHub API work**, so SSH keys are needed only for git transport and signing.

| Item | macOS | WSL2 |
|---|---|---|
| SSH agent | `IdentityAgent` pointing at 1Password's socket | Forward to Windows `ssh.exe` (`core.sshCommand ssh.exe`) |
| Commit signing | `gpg.ssh.program` = `op-ssh-sign` | The snippet from the 1Password app's "Configure for Windows Subsystem for Linux (WSL)" |
| `op` CLI | Desktop app integration (Touch ID) | Windows `op.exe`; the Linux-side `op` cannot use the desktop integration |

Commit signing is decided in [ADR 0005](adr/0005-commit-signing.md).

Known limits:

- `op-ssh-sign` needs the GUI to unlock; it cannot sign headless.
- From some agent tool shells, the `op` desktop integration may not connect. The fallback is a session token from `op signin --raw`, passed with `--session`.
- 1Password's docs do not state how long a CLI desktop-integration authorization lasts, whether it works for processes without a TTY, or whether each signature prompts (**Unverified**).

### GitHub authentication (ghtkn)

See [ADR 0004](adr/0004-github-auth-ghtkn.md).

| Item | Personal (`personal-mac`, `wsl`) | Work (`work-mac`) |
|---|---|---|
| `ghtkn.yaml` | Rendered by `op inject` from `home/.config/ghtkn/ghtkn.personal.yaml.tpl` (client IDs as `op://` references) for a personal GitHub App | `~/.config/dots-work/ghtkn/ghtkn.yaml`: none / read / git / write apps, with the no-permission app first so the default is safe |
| App used by `gh` (`gh-app` file) | `home/.config/ghtkn/gh-app.personal` | `~/.config/dots-work/ghtkn/gh-app` (`<work-gh-org>/write`) |
| Git transport | SSH through 1Password | Work repositories: HTTPS with `ghtkn git-credential`, set in `work.gitconfig` and scoped by `includeIf`. Everything else: SSH |
| aqua | Not used | `AQUA_GHTKN_ENABLED=true`, `GHTKN_APP=<work-gh-org>/read`, set in `env/static.env` so non-interactive shells get them |

- Each machine has exactly one profile. On personal hosts, `~/.config/ghtkn/ghtkn.yaml` is the rendered file; on `work-mac` it links to the work profile.
- The personal GitHub App is created before the first switch of `personal-mac` (Rollout step 1), so `gh` works from day one.
- `gh` is an executable wrapper built with `writeShellScriptBin "gh"`. It calls the real binary as `${pkgs.gh}/bin/gh`. The real `gh` is not in `home.packages`, which would collide with the wrapper's name.
  - If `GH_TOKEN` or `GITHUB_TOKEN` is set, it runs the real `gh` directly.
  - Otherwise it runs `ghtkn exec -e GH_TOKEN:<app> -- <real gh>`. `<app>` is read from `~/.config/ghtkn/gh-app`, a one-line file, so no org name appears in this repository.
  - On exit code 111 (no token), it tells the user to run `ghtkn agent unlock --enable-refresh`.
- The ghtkn agent runs from `launchd.user.agents` on macOS and as a systemd user service on WSL2 (**Unverified** on WSL2).
- Never set `GITHUB_TOKEN`, `AQUA_GITHUB_TOKEN`, or `AQUA_KEYRING_ENABLED`: aqua then ignores ghtkn. Never run `gh auth login`. The `GH_TOKEN` pass-through exists only for a caller that already holds a short-lived token (for example CI).

### Packages

- `nix/packages.nix`: `git`, `ghq`, `fzf`, `ripgrep`, `fd`, `jq`, `neovim`, `just`, `lazygit`, kubectl tooling, `_1password-cli`, `ghtkn` (nixpkgs availability **Unverified**), `mise`.
- Casks on every macOS host: 1Password (the app must exist before any `op` step).
- `hosts/work-mac.nix`: Keeper Secrets Manager CLI (packaging **Unverified**), aqua, internal tools.
- No other language runtimes.
- Font (UDEV Gothic NF): cask on macOS; installed by hand on the Windows side for WSL2.

### Work / personal differences

| Difference | Location |
|---|---|
| GUI apps, internal CLIs | `hosts/work-mac.nix` (public; nothing more sensitive than a tool name) |
| Git identity, work credential helper | `~/.config/dots-work/git/work.gitconfig` (Keeper) |
| Claude Code internal endpoint, internal marketplaces, work plugins, internal MCP | `~/.config/dots-work/claude/` (Keeper) |
| Work-only skills | `home/.claude/skills/work/` if publishable, otherwise `~/.config/dots-work/claude/skills/` (Keeper) |
| ghtkn work apps, app name for `gh` | `~/.config/dots-work/ghtkn/` (Keeper) |
| Internal tokens | Keeper (`keeper://`) |
| CA certificates | See below |

## Bootstrap

```bash
# 1. Install Determinate Nix (on WSL2, enable systemd first)
# 2. Clone over HTTPS (no SSH key is available yet)
git clone https://github.com/<owner>/<repo> ~/src/github.com/<owner>/<repo>
# 3. First switch: installs packages, Homebrew (nix-homebrew), casks including 1Password, and the ksm CLI on work-mac
#    macOS: sudo nix run nix-darwin -- switch --flake .#<host>
#    WSL2:  nix run home-manager -- switch --flake .#<user>@wsl
# 4. Sign in to the 1Password app; enable the SSH agent and CLI integration
# 5. work-mac only: ksm profile init <one-time token>, then scripts/work-sync.sh pull
# 6. Second switch: links the work profile and renders the personal ghtkn.yaml
# 7. Unlock ghtkn (ghtkn agent unlock --enable-refresh)
```

- `scripts/bootstrap.sh` only dispatches the steps above by OS.
- Later runs: `darwin-rebuild switch --flake .#<host>` / `home-manager switch --flake .#<user>@wsl`.
- `justfile` defines exactly `switch`, `update`, and `check`.

## Corporate TLS interception

Each Nix network path reads certificates from a different place (checked against Nix 2.33.0 and nixpkgs 26.05pre source).

| Path | Examples | CA source | Action |
|---|---|---|---|
| Nix's own downloads | Substitution, `github:` inputs, `builtins.fetchurl` / `fetchTarball`, flake registry, git LFS | `ssl-cert-file`, read by both client and daemon | `ssl-cert-file` in `/etc/nix/nix.conf` |
| `builtin:fetchurl` | Bootstrap fetches | The daemon's `ssl-cert-file` | Same |
| nixpkgs `fetchurl` with a known hash | Most source fetches | None: TLS verification is disabled because the hash verifies the content | Nothing |
| Build-time fetches (`fetchgit`, Go / cargo / npm dependencies; whether hashless `fetchurl` belongs here is **Unverified**) | Fixed-output derivations | The daemon's `NIX_SSL_CERT_FILE`, passed through `impureEnvVars` | Set it in the daemon's environment. In the Linux sandbox only `/etc/ssl/certs/ca-certificates.crt` (a bind mount of `ssl-cert-file`) exists, so point the variable there. |
| Derivations that hard-code nixpkgs' cacert | `fetch-yarn-deps`, `buildBazelPackage`, `dockerTools`, `fetchrepoproject` | Fixed to nixpkgs' bundle | Cannot be fixed by configuration. Use only what the binary cache provides. |
| Git-based fetches | `git+https://` inputs, `builtins.fetchGit` | Runs the `git` binary, so the evaluating user's gitconfig applies (which user under `sudo` is **Unverified**) | Prefer `github:` inputs; otherwise `http.sslCAInfo` |
| `hg+https://` | Mercurial inputs | No CA passed to `hg` | Do not use |

- **Precedence**: the manual says `NIX_SSL_CERT_FILE` overrides `ssl-cert-file`, but in 2.33.0 the configured value wins (measured).
- **Bundle**: use the system roots concatenated with the corporate CA, never the corporate CA alone.

**macOS (`work-mac`)**

- Determinate Nixd exports Keychain certificates at start-up. After the certificate store changes, restart Determinate Nixd.
- Determinate's nix-darwin module rejects `ssl-cert-file` in `customSettings` with an assertion.
- How nix-darwin's `security.pki` default `NIX_SSL_CERT_FILE` (`mkDefault "/etc/ssl/certs/ca-certificates.crt"`) interacts with this, and whether Determinate Nixd passes `NIX_SSL_CERT_FILE` to the daemon, are **Unverified**; test on the corporate network.

**WSL2**

- Put the corporate CA in `/usr/local/share/ca-certificates/` and run `update-ca-certificates`.
- `ssl-cert-file` is unnecessary: Nix on Linux uses `/etc/ssl/certs/ca-certificates.crt` by default.
- `systemctl edit nix-daemon` to add `Environment=NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`, then restart the daemon.
- `scripts/ca-bundle.sh` performs these steps.

## CI

- `nix flake check` neither evaluates nor builds `darwinConfigurations` or `homeConfigurations` (measured), so build them explicitly:
  - macOS runner: `nix build .#darwinConfigurations.<host>.system`
  - Linux runner: `nix build .#homeConfigurations."<user>@wsl".activationPackage`
- Generate and check `settings.json` (work side from `profiles/work.example/`).
- Tests for hooks, skills, and scripts.
- gitleaks.
- Monthly: run the bootstrap on a fresh macOS user account or Linux VM.

## Acceptance criteria

- [ ] A fresh macOS / WSL2 machine is ready after one bootstrap run (first-time 1Password, Keeper, and ghtkn authentication excepted)
- [ ] `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -c 'command -v gh ghq fzf rg'` succeeds on every host
- [ ] A project tool installed with the project layer's default resolves from `zsh -c` inside that project
- [ ] Orca sees `gh` and can show PRs; record whether Orca starts zsh
- [ ] Claude Code can use `gh` and `git`, and standard commands print unmodified output
- [ ] `gh` in a non-interactive shell works with a ghtkn token, and `~/.config/gh/hosts.yml` holds no token
- [ ] `gh` uses the work app on `work-mac` and the personal app on `personal-mac`; neither host has the other's `ghtkn.yaml`
- [ ] On `work-mac`, HTTPS push to a work repository succeeds through `ghtkn git-credential`, and push to a personal repository succeeds over SSH
- [ ] Repositories under `~/src/github.com/<work-gh-org>/` (including linked worktrees) use the work identity; all others use the personal one
- [ ] On `work-mac`, `zsh -c 'echo $AQUA_GHTKN_ENABLED'` prints `true`
- [ ] `~/.claude/settings.json` on `work-mac` contains the work plugins and internal endpoint; on `personal-mac` it does not
- [ ] With 1Password locked, an SSH `git fetch` and a signed commit go through with Touch ID alone
- [ ] Run 5 agents in parallel in Orca for an hour and record how many 1Password prompts appear (input to ADR 0005)
- [ ] Opening a new terminal raises no prompt during shell start-up
- [ ] On `work-mac`, `nix flake update` followed by a switch passes with no CA error
- [ ] Grepping this repository finds no internal endpoint, internal marketplace name, work org name, or `keeper://` reference
- [ ] No plain-text token on disk outside the rendered files the design lists (gitleaks over `$HOME`'s managed and rendered files finds nothing)
- [ ] A deliberately broken darwin or home configuration fails CI
- [ ] Each guard hook still denies its target input when run with `env -i PATH=<empty dir>`
- [ ] Breaking one condition of a guard makes its test fail
- [ ] `.zshrc` defines at most 5 aliases

## Open questions

- Whether to enable the Bash sandbox by default, after measuring the sockets and network calls it must allow.
- Whether to auto-start a terminal multiplexer (tmux / herdr) in interactive shells at all.
- Whether Keeper Secrets Manager is available at work (ask IT).
- 1Password auto-lock timeout.
- How to run the ghtkn agent on WSL2.
- Repository name.

## Rollout

1. Create this repository with the minimum: flake, `.zshenv`, `.zshrc`, git, ssh, `~/.claude`. Create the personal GitHub App for ghtkn.
2. Switch `personal-mac`. Move the ghq root to `~/src`.
3. Run it for one to two weeks; pull in from the old repository only what is missed, judged by P6.
4. Roll out to WSL2 (enable systemd first).
5. Roll out to `work-mac`: set up KSM, pull the work profile, verify CA handling.
6. Remove devbox global.
7. Archive the old repository. Decide first what to do about the company settings in its history.
