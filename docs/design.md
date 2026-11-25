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
9. **Works from the Orca mobile app with nobody at the host**: an agent loop started from a phone never waits on a prompt that only the host's screen can answer.

## Non-goals

- Rewriting config file contents in the Nix language (no `programs.*` generation).
- Managing the Windows side (`%USERPROFILE%`) of WSL2 hosts, apart from the Windows apps listed under Packages (Windows Terminal, Orca, 1Password, its CLI, Raycast, the font), which are installed by hand on Windows.
- Maximum shell start-up speed.
- Human-oriented shortcuts (aliases, functions).
- Exhaustive macOS defaults: start empty, add only what is missed.

## Principles

| # | Principle | Meaning |
|---|---|---|
| P1 | PATH is built in `.zshenv` and holds only real executables | No reliance on aliases, functions, or shell hooks. A wrapper, when needed, is an executable. |
| P2 | Never shadow standard commands | No `ls`/`cat`/`grep`/`find` aliases. Use `eza`/`bat`/`rg` under their own names. |
| P3 | Nix wires, files configure | Nix handles packages, symlinks, and the small generators named in this design (generated agent settings, the `gh` wrapper, hook builds). Config content stays in plain files. |
| P4 | Lock files are committed | `flake.lock` is tracked and updated explicitly. |
| P5 | Agent config is a first-class asset | `~/.claude/` and `~/.codex/` are covered by tests and CI. |
| P6 | Two questions before adding anything | Does it reach a process without an interactive shell? Does it remove a human interruption? If neither, leave it out. |
| P7 | Secrets come from a vault | Secret values never live in this repository. `op://` references for the personal profile may (they are pointers that need the account to resolve). Anything identifying the company, including `keeper://` references and org names, lives only in the work profile. gitleaks guards against leaks. |
| P8 | Nix first | A tool comes from the first source that has it: a nix-darwin or home-manager module, then a nixpkgs package, then a Homebrew cask through nix-homebrew, then a manual install. Each tool on a later rung names why the earlier ones do not work. |

## Hosts

| Host | OS | Stack |
|---|---|---|
| `personal-mac` | macOS arm64 | Determinate Nix + nix-darwin + home-manager (darwin module) |
| `work-mac` | macOS arm64 | Same, with the work profile |
| `wsl` | WSL2 Ubuntu (personal PC) | Determinate Nix (requires systemd) + standalone home-manager |

Host names are placeholders. Only `work-mac` carries the work profile and sits behind the corporate proxy. WSL2 also uses Determinate Nix: installing upstream Nix through the Determinate installer needs `--prefer-upstream-nix`, which the installer README calls unsupported and possibly removed in a future release. See [ADR 0001](adr/0001-nix-stack.md).

## Architecture

| Layer | Owner | Responsibility |
|---|---|---|
| Nix | Determinate Nix | Install and update Nix; import Keychain CAs on macOS |
| System (macOS) | nix-darwin + nix-homebrew | Casks (nix-darwin's homebrew module does not install Homebrew, and activation aborts when Homebrew is missing, so nix-homebrew installs it), launchd agents |
| User (all hosts) | home-manager | `home.packages`, symlinks, generated `settings.json` |
| Config files | Plain files in `home/` | zsh, git, nvim, ghostty, Claude Code, Codex |
| Work profile | Files fetched from Keeper into `~/.config/dots-work/` (untracked) | Internal endpoints, internal plugin marketplaces, ghtkn work apps, work git identity |
| Project | One default tool per project (see below) | Language runtimes and project tools |

### Nix layer

- nix-darwin sets `nix.enable = false`; Determinate manages Nix. nix-darwin aborts activation when it detects Determinate with `nix.enable` on. With Determinate's nix-darwin module, this is set automatically and Nix settings go in `determinateNix.customSettings`.
- Cost: nix-darwin's `nix.*` options and its Linux builder are unavailable.
- A Mac that already has Homebrew at `/opt/homebrew` needs `nix-homebrew.autoMigrate = true`; without it activation exits with an error. Migration replaces the Homebrew installation and keeps installed packages.
- `launchd.user.envVariables` and other per-user options require `system.primaryUser`.

### home-manager symlinks

- `mkOutOfStoreSymlink` takes the checkout's **absolute path as a string**. A flake-relative path such as `./home/.zshrc` evaluates to the flake's copy in the store, so the link points there and edits do not show up.
- With absolute paths, edits to existing files apply immediately. Adding, removing, or renaming a linked file needs a switch.
- `~/.config/karabiner` is linked as a whole directory, not file by file, and without home-manager's `recursive` option (default `false`), which would turn `karabiner.json` itself into a symlink. Karabiner-Elements' docs say to link the directory, not `karabiner.json`, because Karabiner fails to detect changes and reload when the file itself is a symlink. Karabiner writes `automatic_backups/` into that directory, so the repository ignores it. Changes made in Karabiner's GUI land in the checkout and show up in `git diff`. Where Karabiner is already running when the link is created (Rollout step 2 on this Mac), its docs require restarting its console user server once: `launchctl kickstart -k gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server`.

### Project layer

- No language runtimes are installed globally.
- The default for new projects is **mise in shims mode** ([ADR 0006](adr/0006-project-layer-mise-shims.md)). The condition it meets: its tools resolve from `zsh -c` without a shell hook. `$ZDOTDIR/.zshenv` puts mise's shims directory (`$XDG_DATA_HOME/mise/shims`; mise uses `MISE_DATA_DIR`, else `XDG_DATA_HOME/mise`) on PATH, and nothing calls `mise activate`. Measured: with only the shims directory on PATH, a non-interactive `zsh -c` ran a project tool declared in `mise.toml`.
- mise tools come from the `aqua:` backend where one exists, never from asdf plugins, and projects commit `mise.lock` (ADR 0006). `home/.config/mise/config.toml` sets `disable_backends = ["asdf"]`, so every host refuses an `asdf:` tool with `backend asdf is disabled by disable_backends` before it fetches anything (measured). It is a host default rather than a lock: a project whose own `[settings]` sets `disable_backends` to something else gets that value, measured in a directory whose `mise.toml` set it to `[]`. `~/.config/mise/config.override.toml` beats a project's settings (measured) but would leave a project that needs an asdf tool no way out, so the overridable default stands.
- Hook-activated environments (direnv, `mise activate`) are not used, because a plain `zsh -c` never sees them.
- Existing projects keep what they use (devbox, a flake devShell). Agents then run commands through `devbox run` / `nix develop -c`, which the project's own CLAUDE.md states.
- Repositories that pin tools in `.aqua.yaml` use aqua, whose bin directory `.zshenv` also puts on PATH.
- Formal-methods tools are project tools, not global packages: their versions belong to the project that uses them. The flake ships `templates` so that a new project gets them in one command ([ADR 0006](adr/0006-project-layer-mise-shims.md)):
  - `nix flake init -t github:paveg/dotfiles#tlaplus`: a flake with a devShell holding nixpkgs' `tlaplus18` (TLA+ tools 1.8.0, which installs `tlc`, `tlasany`, `pcal`, `tlatex`, and `tlarepl`), a small specification `Spec.tla` with its model config `Spec.cfg` (TLC picks up `<Module>.cfg` beside the module, measured), a CI workflow that runs `nix develop -c tlc Spec.tla` on it, and an `AGENTS.md` that tells agents to run the checker that way.
  - `nix flake init -t github:paveg/dotfiles#lean`: a flake with a devShell holding `elan`, plus a `lean-toolchain` file and a minimal Lake project. Lean projects pin their toolchain in `lean-toolchain`, and libraries such as Mathlib follow it, so `elan` installs the toolchain the file names rather than nixpkgs' single `lean4` version. The devShell sets `ELAN_HOME` to `${XDG_DATA_HOME:-$HOME/.local/share}/elan` in its `shellHook`, because elan's default is `~/.elan` (elan reads `ELAN_HOME`, `src/elan-utils/src/utils.rs`). `nix develop -c` runs `shellHook` on upstream Nix 2.33.0 (measured by a review agent); on Determinate Nix the template test decides it. On Linux, nixpkgs' elan patches each toolchain it downloads to use the store's dynamic linker, shell, and C compiler (`0001-dynamically-patchelf-binaries.patch`). Those toolchains live outside the store and are not garbage-collection roots, so a `nix store gc` after a `flake.lock` update may break an installed toolchain; reinstalling it with `elan` repairs it. This is inferred from the source, not run.
  - CI instantiates each template in a temporary directory and runs its own check (`tlc` on the sample specification, `lake build` on the sample project), so a template that no longer works fails here, not in a new project.

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
| A private git repository for company config | Puts company information on a personal GitHub account. Keeper, which the company provides, holds it instead. See [ADR 0002](adr/0002-vaults-and-work-profile.md). |
| apm (Agent Package Manager) | Pre-1.0, and key preconditions (several user-scope manifests) are unverified. Revisit if third-party plugins grow enough to need version pinning. |

## Repository layout

Repositories live at `~/repos/github.com/<owner>/<repo>`, managed with ghq (`ghq.root = ~/repos`). This checkout is `~/repos/github.com/paveg/dotfiles`; every absolute path the flake links to derives from that one location.

```
.
├── flake.nix                 # inputs, host wiring, formatter and checks
├── flake.lock
├── hosts/{personal-mac,work-mac,wsl}.nix
├── nix/
│   ├── darwin.nix
│   ├── home.nix              # packages, symlinks
│   ├── packages.nix
│   ├── agents.nix            # ~/.claude and ~/.codex wiring, hook builds
│   └── vaults.nix            # 1Password, Keeper, ghtkn wiring
├── home/
│   ├── .zshenv               # sets ZDOTDIR and sources the real one
│   ├── .config/zsh/{.zshenv,.zprofile,.zshrc}
│   ├── .config/atuin/config.toml
│   ├── .config/mise/config.toml  # global settings; refuses the asdf backend
│   ├── .config/git/{config,ignore,personal.gitconfig}
│   ├── .config/ghtkn/{ghtkn.personal.yaml.tpl,gh-app.personal}
│   ├── .config/1Password/ssh/agent.toml
│   ├── .config/{nvim,ghostty}/
│   ├── .config/karabiner/        # linked as a directory; automatic_backups/ ignored
│   ├── .config/raycast/scripts/  # Raycast Script Commands
│   ├── .ssh/config
│   ├── .claude/              # CLAUDE.md, rules/, agents/, references/, hooks/ (sources), settings.{common,personal}.json
│   ├── .codex/               # config.toml source (written as a regular file at activation)
│   └── .local/bin/
├── profiles/work.example/    # shape of the work profile, empty values, used by CI
├── tests/
├── scripts/{bootstrap.sh,work-sync.sh,unattended-setup.sh}
├── templates/{tlaplus,lean}/  # flake templates for formal-methods projects
├── spec/                     # TLA+ models and check.sh (TLC plus one mutant per property)
├── docs/
├── .github/workflows/
├── justfile
├── lefthook.yml
├── .gitattributes            # *.md conflict-marker-size=32 (ADR 0008)
├── AGENTS.md
├── CLAUDE.md                 # imports AGENTS.md
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
- This repository links to it with absolute-path `mkOutOfStoreSymlink`. If the directory is missing, the links dangle and the switch still succeeds (home-manager does not check link targets). home-manager prints no warning for a dangling link, so a custom `home.activation` step checks for the directory and warns. Every consumer tolerates the missing profile: git silently ignores a missing include file (measured), `.zshenv` sources `static.env` only if it exists, and the `settings.json` merge falls back to the common file alone.

## Detailed design

### Shell

- `~/.zshenv` is the only zsh file in `$HOME`. It sets the four XDG base directories to the spec defaults when unset (`XDG_CONFIG_HOME=~/.config`, `XDG_DATA_HOME=~/.local/share`, `XDG_STATE_HOME=~/.local/state`, `XDG_CACHE_HOME=~/.cache`), sets `ZDOTDIR=$XDG_CONFIG_HOME/zsh`, and sources `$ZDOTDIR/.zshenv`. zsh reads `~/.zshenv` before it knows `ZDOTDIR`, so that file cannot move.
- `$ZDOTDIR/.zshenv` (every shell): PATH (Nix profiles, `/etc/profiles/per-user/$USERNAME/bin`, `~/.local/bin`, mise shims, aqua's bin directory), `EDITOR`, and `~/.config/dots-work/env/static.env` if it exists. No secrets.
  - Login shells: macOS's `/etc/zprofile` runs `path_helper`, which runs after `~/.zshenv` and moves the system directories to the front of PATH. Measured in a temporary `HOME` on this Mac (no nix-darwin): the first PATH entry set in `.zshenv` stayed first under `zsh -c` and became `/usr/local/bin` under `zsh -lc`, so `/usr/bin/git` would win over Nix's. `$ZDOTDIR/.zprofile`, read after `/etc/zprofile`, therefore puts the same directories back in front. A review agent read nix-darwin's `modules/programs/zsh/default.nix`: with `programs.zsh.enable` (default `true`) it generates `/etc/zprofile` with no `path_helper` call. Whether that replaces Apple's file on a given host is **Unverified**, so `.zprofile` keeps the fix either way, and the bootstrap tests check login-shell PATH after a real switch.
  - nix-darwin's `/etc/zshenv` adds `/etc/profiles/per-user/$USER/bin`, and `$USER` is a literal expanded at run time. Under `env -i` zsh leaves `USER` empty but still sets `USERNAME` and `LOGNAME` (measured), so that entry becomes `/etc/profiles/per-user//bin`. The `$USERNAME` entry above covers it.
- Environment variables are written by hand in plain files, not generated from one Nix source (ADR 0001). A variable that a process started without zsh also needs (a GUI app, the ghtkn agent) is repeated in `launchd.user.envVariables` on macOS or `~/.config/environment.d/` on WSL2, and a CI test checks that each repeated value equals the one in `$ZDOTDIR/.zshenv`. Variables left at their spec defaults need no repetition.
- XDG policy: a tool that already follows the XDG variables needs nothing. A tool that needs its own variable to move (for example `KUBECONFIG`, `CLOUDSDK_CONFIG`, `DOCKER_CONFIG`) gets it in `$ZDOTDIR/.zshenv`, and only after its support is checked; each tool's support is **Unverified** until then. Two limits apply. A process that does not start through zsh never sees these variables, which is why the defaults are the spec defaults. A moved credential path must also move in the `permissions.deny` `Read(...)` rules; a CI test compares the paths exported in `$ZDOTDIR/.zshenv` with those rules, so the two cannot drift.
- Expected not to move (both **Unverified**): `~/.ssh`, which OpenSSH reads from the home directory, and git include paths, which expand `~` but not environment variables. `~/.claude` and `~/.codex` stay where they are until `CLAUDE_CONFIG_DIR` / `CODEX_HOME` are shown to reach Orca-launched agents.
- `$ZDOTDIR/.zshrc` (interactive only): completion cache in `$XDG_CACHE_HOME/zsh`, key bindings (`Ctrl+g` for ghq + fzf, `Ctrl+r` for atuin), plain prompt. Sources `$ZDOTDIR/.zshrc.local` (untracked, non-secret local settings) if present. The zsh files are linked one by one, so `~/.config/zsh` is a real directory and `.zshrc.local` stays outside the checkout; `.gitignore` also lists it. A setting worth keeping moves into the repository.
- zsh keeps history in memory only (`SAVEHIST=0`, `HISTFILE` unset), so up-arrow works within a session and atuin is the only history on disk. A zsh history file would bypass every filter atuin applies. Both settings are made in `.zshrc`, because macOS's `/etc/zshrc` sets `HISTFILE` after `.zshenv` runs.
- `.zshrc` creates `$XDG_CACHE_HOME/zsh` when it is missing, so a fresh machine needs no switch step for it. zsh does not create the parent directory of a file it writes; for a history file it prints `locking failed … no such file or directory` at exit and saves nothing (measured).
- Aliases: none by default. At most short forms that shadow nothing, such as `g=git`.

### Shell history (atuin)

See [ADR 0009](adr/0009-shell-history-atuin.md). `$ZDOTDIR/.zshenv` sets `ATUIN_HOME=$XDG_DATA_HOME/atuin`: atuin's default home is `~/.atuin`, and it uses `XDG_DATA_HOME` only as a fallback for older installs (`crates/atuin-common/src/dirs.rs`), so without the variable a fresh machine gets a new entry in `$HOME`. atuin reads its config from `$XDG_CONFIG_HOME/atuin` when `$ATUIN_HOME` holds none (by a review agent). atuin records interactive commands in SQLite with directory, exit code, duration, and session, so the history can be analysed for repeated or failing steps. Commands that agents run through `zsh -c` are not recorded, because atuin's zsh integration uses `preexec` / `precmd` / `zshaddhistory` hooks that do not fire in a non-interactive shell (measured by a review agent). The history holds human operations only; agent behaviour is analysed from session transcripts instead. atuin's opt-in agent hooks (`atuin hook claude-code`, `atuin hook codex`) are not installed.

Tokens are kept out of the history, and out of what an AI reads from it, in five layers:

1. Commands never carry tokens: `op run`, `ksm exec`, and `ghtkn exec` pass them as environment variables.
2. `secrets_filter = true` (atuin's default). A command that matches one of its patterns is not saved at all (`should_save` in `crates/atuin-client/src/history.rs`). The patterns in `crates/atuin-common/src/secrets.rs` include AWS key IDs, GitHub PATs, `ghu_` / `ghs_` tokens and refresh tokens, Slack, and Stripe keys; the nixpkgs version (v18.24.8) has the same `should_save` logic (by a review agent). A value assigned to a sensitive name, such as `DB_PASSWORD=…`, is not caught by this filter and is stored as typed. A command that starts with a space is not saved either.
3. `history_filter` adds what layer 2 misses: commands specific to this setup that take a secret as an argument, such as `ksm profile init`, and assignments to variables whose names contain `TOKEN`, `SECRET`, `PASSWORD`, or `KEY`.
4. `auto_sync = false` and `update_check = false`, set explicitly: atuin's default for `auto_sync` is `true` with `https://api.atuin.sh` as the sync address, and its update check calls the same host when built with that feature.
5. An AI reads the history only through `scripts/history-export.sh`, which runs `atuin history list` and passes the output on only if gitleaks finds nothing. atuin's data directory is in the `Read(...)` deny rules, which stops file tools and common Bash reads. It does not stop an agent from running `atuin history list` or `sqlite3` itself: like every hook and deny rule here this is a tripwire, and the boundary is the sandbox's `denyRead` once it is enabled (ADR 0007).

A token that none of layers 1-3 recognises (an internal token typed on the command line) is the residual risk: it stays in atuin's database on the local disk, and the gitleaks scan in layer 5 is the last stop before an AI sees it.

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
  root = ~/repos
[core]
  excludesFile = ~/.config/git/ignore
[include]
  path = ~/.config/git/personal.gitconfig
[include]
  path = ~/.config/dots-work/git/include.gitconfig   # absent on personal hosts; git ignores it
```

```gitconfig
# ~/.config/dots-work/git/include.gitconfig (work profile, not in this repository)
[includeIf "gitdir:~/repos/github.com/<work-gh-org>/"]
  path = ~/.config/dots-work/git/work.gitconfig
```

- Identity switches per directory with `includeIf`. Linked worktrees created from a work repository also get the work identity (measured).
- The `includeIf` names the GitHub org directory, so it lives in the work profile, not here.
- Agent worktrees live in each repository's `.claude/worktrees/<name>`, where Claude Code's worktree isolation puts them (measured: all 10 linked worktrees across the local `paveg` clones sit there); the global ignore lists `.claude/worktrees/`. Where Orca creates its own worktrees is **Unverified**; the `includeIf` holds wherever a linked worktree lives (measured).

### Agent configuration

See [ADR 0003](adr/0003-agent-config-profiles.md).

**Wiring.** `~/.claude` also holds runtime state written by Claude Code (`projects/`, `history.jsonl`, `sessions/`, `plugins/`, `.credentials.json`, and more). Link individual entries, never the whole directory.

| Entry | Wiring |
|---|---|
| `CLAUDE.md`, `rules/`, `agents/`, `references/`, `statusline.sh` | Symlink into this repository |
| Hooks | Not linked. Built into the store from `home/.claude/hooks/` and referenced from `settings.json` by store path (see Guardrails) |
| `skills/<name>` | Symlinked per profile (below) |
| `settings.json`, MCP config | Generated by merging common and profile JSON (below) |
| Everything else | Not managed |

Codex (`~/.codex/`) follows the same rules, with two differences:

- Codex reads its global instructions from `~/.codex/AGENTS.md` (or `AGENTS.override.md`), not from `~/.claude/CLAUDE.md`. Both paths link to the same file in this repository.
- Codex writes to `config.toml` at run time (for example project trust levels), resolving symlinks to write the target. A store-linked file would fail that write, so `config.toml` is written as a regular file at activation, like `settings.json`.

**Skills per profile.**

```
home/.claude/skills/{common,personal,work}/<name>/
~/.config/dots-work/claude/skills/<name>/      # work-only, not public
```

`nix/agents.nix` lists `common` plus the host's profile with `builtins.readDir` and links each skill flat into `~/.claude/skills/<name>`. There is no exclusion list. A name present in two profiles is an evaluation error.

Pure evaluation cannot read `~/.config/dots-work/` (absolute paths outside the flake are forbidden, measured), so work-profile skills are linked by an activation script instead. That script also fails on a name that already exists in `~/.claude/skills/`.

**Generated `settings.json`.**

- Activation deep-merges `settings.common.json` with the profile's JSON (`settings.personal.json` in this repository, or `~/.config/dots-work/claude/settings.work.json`) using jq, and writes `~/.claude/settings.json` as a regular file. If the work file is missing, the common file is used alone and activation warns.
- Not a store symlink: Claude Code writes to `settings.json` (installing a plugin at user scope adds it to `enabledPlugins`). Claude Code's docs say that when the file is generated or read-only, such a change lasts only for the current session.
- Changes made inside Claude Code are overwritten by the next switch. The switch prints the diff between the generated file and the current one first.
- Orca also writes this file. At app start (and when its hook setting changes) it merges 16 hook entries whose command runs `~/.orca/agent-hooks/claude-hook.sh`, keeping every other key, and backs the old file up to `settings.json.bak`. Those entries carry agent status to Orca and let Orca answer `PreToolUse` and `PermissionRequest` (that the iOS app relays those answers is **Unverified**). Orca does not restore them until it restarts.
- Orca reads the whole file, merges, and renames a new file over it, with no lock and no check that the file is unchanged. Claude Code takes `settings.json.lock` and re-reads inside it, but neither Orca nor the generator takes that lock. So a write that lands between another writer's read and write is lost. TLC found both directions on the first design (below): a switch dropping Orca's entries, and Orca, from a read taken before the switch, dropping the guard hooks.
- The generator therefore writes Orca's 16 entries itself, from a copy kept in `nix/agents.nix`, instead of carrying them over from the file it read, so a switch never drops them; a stale write by Claude Code or by Orca's own theme sync still can. When Orca changes its entries, the switch's diff shows the difference, assuming the copy matches what Orca writes on that host (measured on one Mac only; what Windows Orca writes into the `wsl` file is **Unverified**). Orca rewrites its own version at its next start either way.
- On macOS the guard hooks and `permissions.deny` are also written to a managed-settings drop-in, `/Library/Application Support/ClaudeCode/managed-settings.d/50-dotfiles.json`. It holds the same merged lists as `settings.json` (common plus profile), so the work deny rules are in it on `work-mac`. The switch writes the drop-in before `settings.json`; TLC shows the guards can drop out during the first switch if the order is reversed. The file is root-owned and world-readable (Claude Code skips a managed file it cannot read), so the agent cannot change it without sudo. That nix-darwin's activation, which runs as root, writes it and reads the work profile for it is the plan; the option it uses is **Unverified**.
- Claude Code merges hook entries and lists across settings levels, and runs a handler defined in two files once. A switch that changes a guard's store path can leave the old path in `settings.json` (a stale write by Orca) next to the new one in the drop-in; whether Claude Code then runs both is **Unverified**.
- The guards in the drop-in are protected only while it is the only writer of that file and Claude Code reads it. Claude Code uses only the highest-ranked managed source: when the employer delivers server-managed settings or an MDM profile on `work-mac`, the drop-in is ignored. Then only the copy in `settings.json` remains, and the race above can drop it until the next switch.
- On `wsl` no drop-in is written. Standalone home-manager runs as the user, so writing `/etc/claude-code/` would need a sudo step in the bootstrap unless the directory is writable by the user on that host (**Unverified**). Either way, Claude Code's docs call it user-writable on WSL, so a drop-in there would not keep the agent out. There the guards live only in `settings.json`, and the race above can drop them until the next switch.
- Only the guards move to managed settings. Other keys change behaviour there (a managed `enabledPlugins` entry cannot be turned off by the user, a managed `model` overrides a `/model` choice at each session start), so they stay in `settings.json`.
- The merge concatenates and de-duplicates arrays instead of using jq's plain `*`, which replaces them. Profiles need their own array entries: the work profile adds `permissions.deny` rules (cloud, cluster, and infrastructure CLIs) that must not apply to personal hosts.

**Environment facts for agents.** `~/.claude/CLAUDE.md` (the same file as `~/.codex/AGENTS.md`) states:

- where repositories live (`~/repos/github.com/<owner>/<repo>`, through ghq);
- global tools are added to `nix/packages.nix`, never with brew or `npm -g`;
- project tools come from the project layer's default;
- GitHub tokens come from ghtkn: never run `gh auth login` or export a token.

**Guardrails.** See [ADR 0007](adr/0007-agent-guardrails.md). Protection is split into three layers: the sandbox enforces Bash reads, writes, and network (enabled only after measurement, below); `permissions.deny` covers Claude's file tools and common Bash forms (for example `Read(~/.aws/**)`); hooks are tripwires for judgements the other two cannot express. Claude Code's docs state that hooks and Bash patterns are not a security boundary, and that a PreToolUse hook that cannot start, exits with a code other than 0 or 2, times out, or prints invalid output lets the call proceed unless it sets `onFailure: "block"` (Claude Code v2.1.295 or later; no effect on `async` hooks).

This repository manages only hooks whose need spans repositories. A hook that concerns one project lives in that project's `.claude/settings.json`, as one repository already does for its own `UserPromptSubmit` guard; the other repository-level settings checked only enable plugins. Each hook below was kept on evidence from the 70 active `paveg` repositories and from past sessions (counts in [`verification.md`](verification.md)).

Hooks come in three kinds, decided by what a failure of the hook should do:

- **Guard**: protects data or credentials. It fails closed (`onFailure: "block"`, explicit `deny` on malformed input).
- **Checker**: enforces a writing or code-quality rule. It denies on a match with a reason the agent can act on, but fails open: a bug in a style check must not halt an unattended agent loop.
- **Injector**: adds context. It never blocks and fails open.

| Hook | Event (matcher) | Kind | Fate |
|---|---|---|---|
| Destructive-database guard | PreToolUse (Bash) | Guard | Kept, rebuilt with `writeShellApplication`. 14 of the 70 active repositories carry drizzle configs or SQL migrations |
| Credential-read guard | PreToolUse (Bash) | Guard | Kept until the sandbox's `denyRead` is enabled and measured on the host, then removed. `Read(...)` deny rules alone miss Bash reads they do not recognize (`grep -r`, a script that opens files itself) |
| Unsigned-commit guard | PreToolUse (Bash) | — | Removed. Replaced by deny rules for `--no-gpg-sign`, `-c commit.gpgsign=false`, and `git config … commit.gpgsign`, plus GitHub's "require signed commits". Revisited with the unattended-signing question |
| Comment-rot check | PreToolUse (Write, Edit, MultiEdit, Bash) | Checker | Kept, rewritten from Python |
| PR-body, browser, and Japanese-writing context | PreToolUse (Bash; `mcp__claude-in-chrome__*`; Write, Edit) | Injector | Kept |
| Unaddressed-request check | Stop (`type: "agent"`) | Checker | Kept as a prompt in `settings.common.json`; there is no script to build |

Entries owned by other tools, as listed in `nix/agents.nix`:

| Owner | Entries | Identified by | How the generator keeps them |
|---|---|---|---|
| Orca | 16 hooks (agent status, `PreToolUse` and `PermissionRequest` decisions by Orca) | `agent-hooks/claude-hook` | Writes them itself (see Generated `settings.json`) |
| herdr | 1 `SessionStart` hook, kept only if herdr is adopted (see Open questions) | `herdr-agent-state.sh` | Carries it over from the current file, which a concurrent write can lose |

- `onFailure` does not cover a guard that exits 0 with no output: plain stdout is not a failure, so the call proceeds. It proceeds through the normal permission flow; exit 0 with no output is not an approval. A guard must never print `allow`, because `allow` skips the permission prompt. So a guard prints `deny` on a match and nothing otherwise, and the risk to close is a guard that errors before reaching its `deny`. Shell error handling does not close it in general (measured): `errexit` (on by default in `writeShellApplication`) is suspended inside `if`, `&&`, `||`, and `!`, and inside `$(…)` unless `shopt -s inherit_errexit` is set, which `writeShellApplication` does not do. What the guard design guarantees, and what it does not:
  - Guaranteed: a dependency cannot be missing (pinned, `inheritPath = false`), and a guard that aborts with an exit code other than 0 or 2 is blocked by `onFailure: "block"`.
  - Narrowed, not guaranteed: an internal error that the script reads as "no match" lets the call through to the normal permission flow. A matcher that errors inside `if grep …` is the measured case. Guards set `shopt -s inherit_errexit`, and check matcher exit codes explicitly (`grep` returns 1 for no match and 2 for an error; only 1 counts as no match).
  - The remaining gap is why guards are tripwires rather than a boundary, and why the upgrade condition below exists.
- Every script hook is built with `writeShellApplication` with `inheritPath = false`: `runtimeInputs` pins `jq`, coreutils, and grep, so nothing is resolved from the caller's PATH, and shellcheck runs at build time. The default, `inheritPath = true`, appends the caller's PATH. The generated `settings.json` refers to hooks by store path.
- A running guard is a store path, so editing its source in this repository changes nothing until the next switch, which a human runs. An `Edit` deny rule on `~/.claude/settings.json` stops the agent from repointing hooks by accident. Neither stops a hostile agent. On `personal-mac`, and on `work-mac` when no higher managed source applies, the guards' managed copy is root-owned, so removing the copy in `settings.json` does not disable them. On `wsl` there is no managed copy (see Generated `settings.json`).
- Sandbox: Claude Code's docs say that on macOS, with `allowUnixSockets` unset, the sandbox blocks every Unix socket. The 1Password SSH agent socket, the ghtkn agent, and the Nix daemon socket must be listed there. On Linux and WSL2 that list is ignored and only the all-or-nothing `allowAllUnixSockets` applies. Set `failIfUnavailable: true`, because by default Claude Code runs commands unsandboxed when the sandbox cannot start. Before enabling it with `allowUnsandboxedCommands: false`, measure on each host that those sockets and `op` / `ksm` still work.
- Upgrade condition: if a concrete bypass of the database guard needs closing (for example through `bash -c`), rebuild that guard as a Go binary that parses commands into a syntax tree.

**Safe updates.** Hooks, skills, and scripts ship with tests that run in CI. Each guard's test is shown to fail when the guard is deliberately broken. CI also generates `settings.json` and checks that it is valid JSON and contains the required hooks and Orca's entries, and that the macOS drop-in contains the guards, using `profiles/work.example/` for the work side.

### Secrets

See [ADR 0002](adr/0002-vaults-and-work-profile.md).

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
- Credentials that tools keep on disk by their own design, and that this repository does not try to move into a vault:
  - the 1Password and Keeper Secrets Manager device configs (with keyring support, the KSM CLI stores its config in the macOS Keychain);
  - agent CLI logins (`~/.claude/.credentials.json` where Claude Code does not use the Keychain, `~/.codex/auth.json`);
  - cloud and cluster CLI credentials used for SRE work (for example `gcloud` and kubeconfig tokens). `permissions.deny` `Read(...)` rules cover their paths;
  - Tailscale's node key, in `tailscaled`'s state on `personal-mac` (ADR 0010).
- gitleaks runs as a pre-commit hook through lefthook and in CI ([ADR 0008](adr/0008-repo-checks-lefthook-treefmt.md)).
- Prerequisite: whether Keeper Secrets Manager needs admin enablement or an extra license is not covered by Keeper's docs; ask company IT. If it is unavailable, the work profile stays local to `work-mac` and is recreated by hand on a new machine.

### 1Password agent and prompts

1Password raises two kinds of prompts.

| Prompt | When | How to reduce it |
|---|---|---|
| Unlock | 1Password is locked | Unlock with Touch ID (Windows Hello on Windows). Set the auto-lock timeout in 1Password. |
| Key approval | By default per key and per application (a stricter per-terminal-session option exists). An approval lasts until 1Password locks or quits, or for a set time if one is chosen. | See below |

- **Only a timed approval survives locking.** Per 1Password's docs, an approval given for a set time (for example four hours) stays in the agent's memory across a lock, and only unlocking is asked again. The default approval ends when 1Password locks. Either way, a locked 1Password needs an unlock on the Mac itself.
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
- A CLI desktop-integration authorization is tied to the current TTY and expires after 10 minutes of inactivity, 12 hours at most (1Password's app-integration security page, by a review agent). Whether it works for processes without a TTY, and whether each signature prompts, are **Unverified**.

### Unattended host (Orca mobile)

The Orca iOS app is a viewer: terminals, git, and agents run on the paired desktop, or on a headless `orca serve` host. A direct or LAN session drops when the desktop app closes, and a remote server must stay awake and on the same LAN or tailnet. Every human step falls into one of three classes:

1. No interaction.
2. Answerable in a terminal, and so from the phone, which the App Store listing says mirrors terminals with full keyboard input. Orca's hook also hands Claude Code's permission requests to Orca (see Agent configuration); that the iOS app shows and answers them is **Unverified**.
3. Host screen only: a GUI dialog, Touch ID, or Apple Watch unlock, which needs the watch close to the Mac.

Goal 9 means no class 3 step on the unattended path. With the design as it stands:

| Agent step | At the desk | Away, 1Password locked |
|---|---|---|
| `gh`, GitHub API | 1 (ghtkn agent) | 1 while the agent stays unlocked; after a restart, `ghtkn agent unlock` (class 2 or 3, **Unverified**) |
| `git fetch` / `push`, work repositories | 1 (HTTPS + `ghtkn git-credential`) | 1 |
| `git fetch` / `push`, personal repositories | 3 at most once per approval (SSH through 1Password) | 3: blocks |
| Signed commit | 3, at least once per approval (`op-ssh-sign`; whether each signature prompts is **Unverified**) | 3: blocks |
| `op run` / `op inject` | 3: an authorization lasts per terminal until 10 minutes of inactivity, 12 hours at most (by a review agent); without a TTY, **Unverified** | 3: blocks |
| `ksm exec` | 1 | 1 if the KSM config in the Keychain stays readable with the screen locked (**Unverified**) |
| Switch (`sudo`) | 2. Rendering the personal `ghtkn.yaml` through `op inject` is 3, so the switch renders it only when the file is missing or its template changed (a hash of the template is stored beside it), and only when 1Password is signed in; otherwise it skips with a warning. At bootstrap step 5 1Password is not signed in yet, so the first render happens at step 8, at the desk | 2 from Orca's terminal on the host, once Orca has App Management, unless the template changed; 3 over Tailscale SSH, which fails nix-darwin's App Management check without Full Disk Access (see Packages). Whether Orca's terminal counts as a GUI session for that check is **Unverified**. How the switch detects "signed in" without itself raising a prompt is **Unverified** |

- 1Password has a "Lock when device locks or sleeps" setting (its default is not documented). A locked 1Password prompts on the Mac; its docs say nothing about answering from another device.
- The two acceptance criteria that involve 1Password prompts assume someone at the Mac; they do not cover this scenario.
- Using HTTPS with `ghtkn git-credential` for every GitHub repository, as work repositories already do, removes the personal fetch/push row. SSH stays for hosts other than GitHub.
- Signed commits and `op` are open (see Open questions).

**The unattended host** is `personal-mac` itself ([ADR 0010](adr/0010-unattended-host-reachability.md)):

- `orca serve service install` keeps Orca's server running as a LaunchAgent, independent of the desktop app. Orca writes that LaunchAgent itself, so nix-darwin does not own it; `scripts/unattended-setup.sh` runs the install command (below), and `orca serve service status --json` is how the design checks it. Orca's help says a packaged macOS app's server runs Electron, which needs a desktop login, and that `ORCA_SERVE_RUNTIME=orcad` runs a Node server instead when nobody is logged in (measured: `orca serve --help`).
- nix-darwin's `power.sleep.computer = "never"` keeps the Mac awake. How a laptop behaves with the lid closed or on battery under this setting is **Unverified**.
- Tailscale, through nix-darwin's `services.tailscale` on `personal-mac` only, makes the host reachable from the phone outside the LAN. `orca serve` already accepts Tailscale addresses (100.64/10 and fd7a:115c:a1e0::/48) without `--allow-public` (measured: `orca serve --help`). Tailscale SSH is the way back into the host when Orca itself is stuck. Key expiry is disabled for this device only; otherwise re-authentication becomes a class 3 step every 180 days (Tailscale's default, by a review agent). `work-mac` gets no Tailscale: a personal VPN on a company machine is not this repository's decision. `wsl` gets none until it runs agents unattended.
- FileVault is on (measured: `fdesetup isactive` printed `true`). After an unplanned restart the Mac stops at the FileVault unlock screen, so it is unreachable until someone is at the desk. That is class 3 and no setting here removes it. A planned restart uses `sudo fdesetup authrestart`, which asks for the password in the terminal, so starting it from the phone is class 2; whether Orca comes back without a login is not yet known (table below).

**Setup, by hand, on `personal-mac` only.** The bootstrap does not do this, because almost every step needs a person and none can be stubbed in CI. After the bootstrap finishes, the owner runs `scripts/unattended-setup.sh` at the desk. Every `tailscale` call uses `/run/current-system/sw/bin/tailscale`, the open-source build nix-darwin installs, and every `orca` call uses `/Applications/Orca.app/Contents/Resources/bin/orca`, so neither depends on PATH:

1. Orca is already installed by the switch (see Packages); the script stops if `/Applications/Orca.app` is missing.
2. Human: `sudo /run/current-system/sw/bin/tailscale up --ssh`, sign in in the browser, then disable key expiry for this device in Tailscale's admin console. `--ssh` makes the host a Tailscale SSH server.
3. The script runs `orca serve service install --command /Applications/Orca.app/Contents/Resources/bin/orca` with PATH set to `/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`; `/usr/local/bin` is there because nix-darwin's 1Password CLI module installs `op` at `/usr/local/bin/op`. It cannot shadow a Nix tool, because the Nix directories come first (measured on this Mac: the only name in `/usr/local/bin` that a Nix profile also provides is Docker's `kubectl`). The LaunchAgent stores the installing shell's PATH, and without `--command` the install fails under that PATH because it looks `orca` up there (measured: exit 1; with `--command`, the plist runs the given path). These paths are stable symlinks, so later switches need no reinstall.
4. Human, on the phone: install Tailscale and sign in to the same tailnet, then scan the QR code from `orca pair --mobile --address <the host's Tailscale IPv4>` with Orca Mobile. `orca pair --help` says mobile pairing works on the same network or tailnet only, unless `--relay` is given. An SSH client on the phone is what the "Orca is stuck" row below relies on.
5. On a rerun, the script skips Tailscale when `tailscale status --json` reports `BackendState` `Running`, and the service when `orca serve service status --json` reports `"installed": true`. It does not parse the text output, which also lacks "is not installed" when `orca` itself is missing.

| Host event | Away, 1Password locked |
|---|---|
| Orca's server crashes | 1: the LaunchAgent restarts it, until 6 failures in 15 minutes, after which it gives up (`orca serve --help`) |
| Orca is stuck | 2: Tailscale SSH, then `orca serve service` commands |
| Planned restart | 2 or 3: `sudo fdesetup authrestart` unlocks FileVault, but the Orca service is a per-user LaunchAgent and Electron needs a desktop login; whether the restarted Mac runs it before someone logs in is **Unverified** |
| Unplanned restart (power loss, panic) | 3: FileVault unlock at the Mac |

### GitHub authentication (ghtkn)

See [ADR 0004](adr/0004-github-auth-ghtkn.md).

| Item | Personal (`personal-mac`, `wsl`) | Work (`work-mac`) |
|---|---|---|
| `ghtkn.yaml` | Rendered by `op inject` from `home/.config/ghtkn/ghtkn.personal.yaml.tpl` (client IDs as `op://` references) for a personal GitHub App | `~/.config/dots-work/ghtkn/ghtkn.yaml`: none / read / git / write apps. The none app is listed first, but `GHTKN_APP` (below) makes the read app the default |
| App used by `gh` (`gh-app` file) | `home/.config/ghtkn/gh-app.personal` | `~/.config/dots-work/ghtkn/gh-app` (`<work-gh-org>/write`) |
| Git transport | SSH through 1Password | Work repositories: HTTPS with `ghtkn git-credential`, set in `work.gitconfig` and scoped by `includeIf`. Everything else: SSH |
| aqua | Not used | `AQUA_GHTKN_ENABLED=true`, `GHTKN_APP=<work-gh-org>/read`, set in `env/static.env` so non-interactive shells get them |

- Each machine has exactly one profile. On personal hosts, `~/.config/ghtkn/ghtkn.yaml` is the rendered file; on `work-mac` it links to the work profile. ghtkn reads `${XDG_CONFIG_HOME:-$HOME/.config}/ghtkn/ghtkn.yaml`.
- Both `ghtkn.yaml` files set `backend.type: agent`; ghtkn's default backend is the OS keyring, which the agent design does not use.
- `ghtkn exec` never starts the device flow, so exit code 111 means either "the agent is locked" or "not authenticated yet". Bootstrap first runs `ghtkn agent unlock --enable-refresh`, which sets the passphrase and creates the data key, and then `ghtkn auth` once per app: ghtkn's docs say no token can be obtained until the agent is unlocked (that `ghtkn auth` fails against a locked agent is inferred, not run).
- `git-credential` picks its app from `apps[].git_owner` / `git_owners` in `ghtkn.yaml` (with `credential.useHttpPath true` in git config), then `GHTKN_GIT_APP`, then `GHTKN_APP`. `static.env` sets `GHTKN_APP` to the read app for aqua, so the work `ghtkn.yaml` names the write app for the work owner through `git_owners`, with `credential.useHttpPath true` in `work.gitconfig`; otherwise pushes would get a read-only token. Whether aqua's embedded ghtkn honors `GHTKN_APP` is **Unverified**.
- That same `GHTKN_APP` makes the read app, not the no-permission app, the default for any command that names no app. The `gh` wrapper always names its app, so this affects only direct `ghtkn exec` calls.
- The personal GitHub App is created before the first switch of `personal-mac` (Rollout step 1), so `gh` works from day one.
- `gh` is an executable wrapper built with `writeShellScriptBin "gh"`. It calls the real binary as `${pkgs.gh}/bin/gh`. The real `gh` is not in `home.packages`, which would collide with the wrapper's name.
  - If `GH_TOKEN` or `GITHUB_TOKEN` is set, it runs the real `gh` directly.
  - Otherwise it runs `ghtkn exec -e GH_TOKEN:<app> -- <real gh>`. `<app>` is read from `~/.config/ghtkn/gh-app`, a one-line file, so no org name appears in this repository.
  - On exit code 111 (no token), it tells the user to run `ghtkn agent unlock --enable-refresh`.
- The ghtkn agent runs from `launchd.user.agents` on macOS and as a systemd user service on WSL2 (**Unverified** on WSL2).
- Never set `GITHUB_TOKEN`, `AQUA_GITHUB_TOKEN`, or `AQUA_KEYRING_ENABLED`: aqua then ignores ghtkn. Never run `gh auth login`. The `GH_TOKEN` pass-through exists only for a caller that already holds a short-lived token (for example CI).

### Packages

- `nix/packages.nix`: `claude-code` ([ADR 0011](adr/0011-claude-code-from-nixpkgs.md)), `git`, `ghq`, `fzf`, `ripgrep`, `fd`, `jq`, `neovim`, `just`, `lazygit`, `lefthook`, `gitleaks`, kubectl tooling (`kubectl`, `kubernetes-helm`, `k9s`, `stern`; nixpkgs' `helm` is an unrelated synthesizer), `ghtkn` (in nixpkgs), `mise`, `atuin`.
- The 1Password CLI is not a nixpkgs package on any host: on macOS it comes from the module below, and on `wsl` the Windows `op.exe` is used, because the Linux `op` inside WSL cannot use the desktop app integration. Every `op` call on `wsl` (step 8's `op inject` included) means `op.exe`.
- Unfree packages are allowed by name only: `claude-code`, `_1password-gui`, `_1password-cli` (both evaluated by the macOS modules), and `raycast`. `claude-code` is the only unfree package in `nix/packages.nix` (measured), and the predicate lives in `flake.nix`, which is where both the nix-darwin `pkgs` and the standalone home-manager `pkgs` for `wsl` are built.
- macOS apps, by P8's order. nix-darwin copies nixpkgs apps into `/Applications/Nix Apps` with rsync (`modules/system/applications.nix`), so their paths stay the same across rebuilds:
  - nix-darwin modules: 1Password (`programs._1password-gui`, which installs `/Applications/1Password.app`; the app must exist before any `op` step), the 1Password CLI (`programs._1password`, which installs `/usr/local/bin/op`: the module notes that the app integration works only with the CLI at that path), Tailscale (ADR 0010).
  - nixpkgs packages: Raycast (`raycast`, unfree, allowed by name), Ghostty (`ghostty-bin`; nixpkgs' `ghostty` builds for Linux only), and the font (`udev-gothic-nf` through `fonts.packages`).
  - Homebrew casks, only where the earlier rungs do not work:
    - Karabiner-Elements (cask `karabiner-elements`). nix-darwin's `services.karabiner-elements` is broken with Karabiner 15: the module links `org.pqrs.karabiner.agent.*` LaunchAgent plists that the 15.x sources no longer ship, and nix-darwin issue #1041 ("services.karabiner-elements is broken after Karabiner-Elements v15.0") is open, with an activation failure on exactly that. nixpkgs' `karabiner-elements` ships the driver as a separate `driver` output, which the module copied into `/Applications`; installing the package alone would not put the driver there.
    - Orca from its own tap (`homebrew.taps = [ { name = "stablyai/orca"; trusted = true; } ]`, cask `stablyai/orca/orca`; nix-darwin's tap option notes that Homebrew 6.0.0 and later refuse formulae and casks from untrusted non-official taps, aborting activation, while its cask option says such casks are silently skipped and that a fully qualified cask such as `stablyai/orca/orca` is trusted by default; trusting the tap is harmless either way; as Orca's install docs give; nixpkgs' `orca` is the GNOME screen reader, and Homebrew's core `orca` cask is an unrelated, disabled app).
  - The cost of P8 here: nixpkgs lags the vendors (measured: nixpkgs `raycast` 2.10.1.0 against cask 2.13.1.0), and an app copied from the store cannot update itself, so updates arrive with `flake.lock` updates. Whether macOS keeps the privacy approvals of an app in `/Applications/Nix Apps` across rebuilds is **Unverified** and checked on `personal-mac` before `work-mac`.
  - Apps in `/Applications/Nix Apps` make every switch check App Management (`ensureAppManagement` in nix-darwin's `applications.nix`). In a GUI session it resets the App Management decision once, which makes macOS ask for it, and fails until the terminal app running the switch has App Management in System Settings. That reset (`tccutil reset SystemPolicyAppBundles`) names no app, and `tccutil` resets the decision for every app when no bundle ID is given, so one switch from a terminal without the grant also clears the grants of the others; over SSH it fails unless programs run over SSH have Full Disk Access. This repository grants App Management to the terminals the owner switches from (Ghostty, and Orca's terminal) once at the desk, and does not grant Full Disk Access to SSH, which would hand every SSH session access to the whole disk.
- Karabiner-Elements and Raycast are desk tools the owner asked for: neither reaches a process without an interactive shell, so they are a stated exception to P6.
- Karabiner-Elements needs four approvals after install, per its docs: background services, Accessibility, Input Monitoring (normally granted with Accessibility), and its driver extension. They are made once, at the desk. On `work-mac`, whether the company's device management allows the driver extension is **Unverified**.
- Raycast keeps its settings in its own database, not in a file (`~/Library/Application Support/com.raycast.macos/`). The free plan has no Cloud Sync, which needs Pro. So:
  - Script Commands are plain scripts in `home/.config/raycast/scripts/`, which is added once in Raycast's settings as a script directory.
  - Settings, aliases, hotkeys, and extensions are exported with **Export Settings & Data** to an encrypted `.rayconfig` file, stored as a document in 1Password with its passphrase, and imported by hand on a new machine. It never enters this repository: the repository is public, and snippet and quicklink exports are not encrypted.
- `hosts/work-mac.nix`: Keeper Secrets Manager CLI, aqua, internal tools. The KSM CLI is not in nixpkgs, and Keychain storage needs its pip `keyring` extra; without it the config falls back to a plain `keeper.ini`. Packaging it (a local derivation or another installer) is **Unverified**.
- No other language runtimes.
- Font (UDEV Gothic NF): `udev-gothic-nf` from nixpkgs on macOS; installed by hand on the Windows side for WSL2.
- Every `winget install` below behaves the same on a machine that already has the package: winget switches to an upgrade, installs a newer version if there is one, and otherwise exits non-zero: `0x8A15002B` when no applicable update exists, `0x8A150068` when the package is pinned, and `0x8A15008E` when the newer version uses another install technology. `--no-upgrade` leaves an installed copy alone and exits `0x8A150061`. These are manual steps, so a non-zero exit for an installed package is expected, not a failure.
- Windows side of `wsl`, installed by hand. 1Password and its CLI are needed before the bootstrap's step 6, because WSL reaches 1Password only through the Windows app. The others can come at any time, and the bootstrap's closing checklist names them: Windows Terminal stands in for Ghostty, and Orca and Raycast are the apps the owner uses on every machine:
  - Orca: `winget install --id StablyAI.Orca -e` (winget has `StablyAI.Orca` 1.4.274, the same version as Orca's `orca-windows-setup.exe` release). On `wsl` the Windows desktop app is used, because Orca's terminal docs describe its WSL support from Windows: for a repository on the WSL filesystem (`\\wsl.localhost\...`, which is where `~/repos` lives on `wsl`), Orca starts the terminal through `wsl.exe -d <distro>`, and it provides the Orca CLI in those terminals. Orca also ships Linux builds, including a headless `orca-server-linux` tarball, but a server inside WSL would still need a desktop client to work from, and the Windows app is that client and already reaches WSL repositories. Whether git and agents behave in that setup as they do on macOS is **Unverified**; `wsl` is not the unattended host, so this needs to work only at the desk. Orca's `serve` service is not available on Windows (`orca serve service install --help`), nor is `--supervise` (`orca serve --help`).
  - Windows Terminal: `winget install --id Microsoft.WindowsTerminal -e`, the command its repository's README gives. Microsoft's install page does not say that Windows 11 ships with it, so it is installed explicitly. Its `settings.json` lives on the Windows side and is not managed here. Ghostty, the macOS terminal, lists only macOS and Linux builds.
  - 1Password: `winget install --id AgileBits.1Password -e`.
  - 1Password CLI: `winget install --id AgileBits.1Password.CLI -e`. WSL calls the Windows `op.exe`; 1Password's docs say the Linux `op` inside WSL cannot use the desktop app integration and recommend calling `op.exe` from the WSL shell.
  - This relies on WSL's interop staying at its defaults (`[interop] enabled = true`, `appendWindowsPath = true` in `/etc/wsl.conf`): with `enabled` off, WSL cannot start `ssh.exe`, `op.exe`, or 1Password's signer, and with `appendWindowsPath` off, `op.exe` must be called by its full path.
  - Commit signing from WSL needs Git 2.34.0 or later and a 64-bit Windows 10 or later on x64: 1Password's docs say Arm-powered Windows devices are not supported.
- Raycast on every machine. On `wsl` it runs on the Windows side, installed by hand with `winget install raycast` (Raycast's Windows page; Windows 10 21H2+ or Windows 11). Raycast has no manifest in the winget community repository (measured), so that command presumably resolves through the Microsoft Store source. Its settings come from the same `.rayconfig` in 1Password: Raycast's manual says the files are cross-platform. The Script Commands in this repository are macOS shell scripts; Raycast on Windows runs scripts with whatever interpreter is on the Windows PATH, so they are not offered there until a script is written for it.

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

### Formal models (TLA+)

Two parts of this design fail through combinations of state that reviews kept missing: the bootstrap's reruns and skips (an unpushed work-profile edit overwritten on rerun, a step that could never finish when Keeper is unavailable), and several programs writing one `settings.json`. Both are modelled in TLA+ under `spec/` and checked with TLC in CI by `spec/check.sh`, which runs each model and then a mutant copy per property that must fail on that property. CI gets TLC from `nix shell nixpkgs#tlaplus18` until the repository's own `tlaplus` template exists. Lean is not used: nothing here needs a proof beyond what tests show.

- `spec/bootstrap.tla` models the steps of the Bootstrap section as actions over: the recorded host, whether Nix, the checkout, and each switch are present, each human step's check, whether `~/.config/dots-work/` exists and holds unpushed edits, and whether Keeper Secrets Manager is available. A run may stop after any action and be started again. Invariants and properties:
  - a personal host never calls `ksm` and never creates `~/.config/dots-work/`;
  - a host argument that is missing or differs from the recorded one changes nothing;
  - `work-mac` never reaches the end without its work profile;
  - unpushed work-profile edits survive every rerun;
  - from any stopped state, rerunning with the human steps done eventually finishes. This liveness property holds only if the person does not stop the run forever: under weak fairness alone, a behaviour that stops and restarts endlessly violates it (TLC counterexample, reproduced). The model states its assumptions, each added because TLC found a behaviour that broke the property without it: each step has strong fairness (`SF_vars`), so a step enabled again and again is eventually taken; the host check has weak fairness, and strong fairness only for a run with the right host, since halting a wrong-host rerun is not progress; a stopped run is eventually restarted with the intended host (`SF_vars(EnvRestart)`: weak fairness is not enough, because wrong-host reruns keep disabling it); the owner eventually stops naming wrong hosts (`EnvBecomeCareful`), and undoes a wrong first host by the reset below (`EnvResetHost`); and people finish their human steps, including placing the work profile by hand, which they can do while a run is going.
- `spec/settings_writers.tla` models the macOS writers of `~/.claude/settings.json`: the switch's generator, Orca merging its hook entries at app start, Orca's theme sync (which writes back what it read plus a `theme` key), and Claude Code enabling a plugin (herdr is left out until it is adopted). Each reads the file and later writes it back, in any interleaving; the switch writes the drop-in first. Properties:
  - once a switch has written, the guard hooks are in effect in every state;
  - a switch never drops Orca's entries. A stale write by Claude Code or by Orca's theme sync still can; those races are between other tools and outside this design, and TLC shows both are reachable.
  The first design, which kept the guards only in `settings.json` and carried Orca's entries over from the file the generator read, broke both (TLC counterexamples). So did the two fixes this section first proposed (TLC, prototype variants): with the generator re-reading just before writing, Orca's stale write still drops the guards; with the switch restarting Orca, Claude Code's stale write still drops them, and whether a restart ends the agent sessions running in Orca is **Unverified**. The two choices of Generated `settings.json` (guards also in managed settings, Orca's entries written by the generator) are what pass. `check.sh` keeps two mutants: `settings.json` written while the drop-in is missing (the first design's guards), and Orca's entries carried over from the read. The guard property follows from the drop-in, not from the interleavings: it assumes nothing else writes the drop-in and Claude Code reads it (not true when a higher managed source exists, above). The model also assumes the switch writes the drop-in before `settings.json`; the mutant shows the property fails without the drop-in, and no test checks the order in the generator itself, whose tests check only its output (Safe updates).
- The bootstrap model is not the bash script. Each state and transition the model checks becomes a case in the bootstrap tests (CI), so the tests and the model cover the same states.
- The bootstrap model has two kinds of actions. Step actions correspond to the numbered steps of the Bootstrap section, including host-specific ones, and each is a function of the same name in `scripts/bootstrap.sh`. Environment actions have no function: a stop, a restart, a person finishing a human step, Keeper becoming unavailable, an edit to the work profile, and the final `EnvDone`. Their names start with `Env`. CI compares the script's step functions with the model's actions minus the `Env` ones, so a step added to one side only fails CI.
- TLC runs with each model's `<Module>.cfg`. A finished run is a final state, which TLC reports as a deadlock, so the model ends with a stuttering `EnvDone` action instead of turning deadlock checking off.

## Bootstrap

One command on a fresh machine, with the host named explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/scripts/bootstrap.sh | bash -s -- <host>
# <host> is one of personal-mac, work-mac, wsl. There is no default.
```

`scripts/bootstrap.sh` is bash that runs on macOS's bash 3.2, so it uses no bash 4 features and no `inherit_errexit`. It pipes into `bash`, not `sh`, because `sh` is dash on Ubuntu. It runs these steps in order. At each human step it says what to do and continues after checking the result where a check exists (for example that the 1Password SSH agent socket exists); otherwise it waits for Enter. Every prompt reads from `/dev/tty`, because the script's own stdin is the pipe from `curl`.

1. Check `<host>`: it must be one of the listed hosts, match the OS (`wsl` only on Linux, the others only on macOS), and, on a rerun, match the recorded host (step 3). Otherwise exit non-zero before changing anything.
2. Install Determinate Nix if `nix` is missing, then load its profile into the running script. On WSL2 without systemd, stop and say how to enable it. On a Mac with upstream Nix, stop and point to Determinate's macOS package (below).
3. Record `<host>` in `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host`. The XDG variables are not set yet (`~/.zshenv` arrives with the first switch), so the script uses the spec default. `just switch` reads this file, so later switches never take a host name again.
4. Clone over HTTPS with git and ghq from nixpkgs (no SSH key yet; no git is assumed on the host): `GHQ_ROOT=~/repos nix shell nixpkgs#git nixpkgs#ghq -c ghq get https://github.com/paveg/dotfiles`, then work from `~/repos/github.com/paveg/dotfiles`. On an existing checkout `ghq get` prints `exists` and exits 0 without running git (measured).
5. First switch: installs packages and apps, including 1Password on macOS (on `wsl` it is a Windows-side prerequisite), Homebrew (nix-homebrew) on macOS for the remaining casks, and the ksm CLI on work-mac. macOS: `sudo nix run nix-darwin -- switch --flake .#<host>`; WSL2: `nix run home-manager -- switch --flake .#<user>@wsl`. The script then prepends the profile's bin directories (`/etc/profiles/per-user/$USER/bin` on macOS, `~/.nix-profile/bin` on WSL2) to its own PATH, so the tools the switch installed are found in later steps.
6. Human: sign in to the 1Password app; enable the SSH agent and CLI integration.
7. work-mac only, skipped when `~/.config/dots-work/` already exists, so a rerun never overwrites unpushed work-profile edits:
   - If Keeper Secrets Manager is available: human, `ksm profile init <one-time token>`, skipped when a KSM profile already exists; the script then runs `scripts/work-sync.sh pull`.
   - Otherwise: human, place the work profile in `~/.config/dots-work/` by hand (the fallback in ADR 0002), then press Enter.
8. Second switch: links the work profile and renders the personal `ghtkn.yaml`.
9. Human: `ghtkn agent unlock --enable-refresh` sets the passphrase on the first run; then `ghtkn auth` once per app, which runs the device flow in the browser. The order follows ghtkn's docs: no token can be obtained until the agent is unlocked.
10. Install the repository's git hooks (`lefthook install`).
    On macOS the script then prints a checklist of one-time GUI steps: App Management for Ghostty and Orca (needed by the next switch, see Packages), Karabiner's approvals, adding Raycast's script directory, and importing the `.rayconfig` from 1Password (skipped on a first machine that has no export yet). On `wsl` the checklist names the Windows-side steps instead: the `winget install` commands for Windows Terminal, Orca, and Raycast, and the same `.rayconfig` import. 1Password and its CLI are not on the checklist: they are prerequisites, and step 6's check (a stub `ssh-add.exe` in CI, the real one otherwise) fails until they are installed. They are a checklist rather than human steps that wait for Enter, because nothing in the bootstrap depends on them, so they need no check and the run can finish without them.

Work and personal are kept apart by the host, never by guessing:

- The host is a required argument. The script does not infer it from the hostname, the hardware, or a network.
- Only `work-mac` runs step 7, and only `work-mac`'s configuration links `~/.config/dots-work/`. A personal host never calls `ksm` and never creates that directory.
- On `work-mac` the script does not run the second switch until `~/.config/dots-work/` exists, so the machine cannot finish half personal.
- Changing a machine's host, for example after a first run named the wrong one, is done by hand and the script never does it: push any work-profile edits, then delete the recorded host, `~/.config/dots-work/`, and the KSM profile together. Deleting only the recorded host leaves the work profile on what is now a personal machine (TLC counterexample on `spec/bootstrap.tla`).

Notes:

- Every step must be safe to rerun, so a stopped run is resumed by running the same command again. Step 7 achieves this by skipping what already exists; `ksm profile init` itself consumes a one-time token and is never repeated. This is a requirement on the script, not yet a tested property.
- `DOTFILES_REF`, when set, makes step 4 run `git fetch origin <ref>` and `git checkout --detach FETCH_HEAD` in the checkout after `ghq get`, so CI runs the bootstrap against the commit under test. `ghq get` alone cannot do this: it takes only a branch name, and on an existing checkout it runs no git command (measured). Without `DOTFILES_REF`, step 4 never moves an existing checkout.
- The first run executes `scripts/bootstrap.sh` from `main` without a prior review step, which is the same trust as the clone in step 4. Later runs use the checkout: `scripts/bootstrap.sh <host>`.
- `GHQ_ROOT` overrides ghq's root before any git config exists (measured: `GHQ_ROOT=/tmp/x ghq root` printed `/tmp/x`).
- An existing Mac that runs upstream Nix (this one does: `nix (Nix) 2.33.0`, no `determinate-nixd`, measured) switches with Determinate's macOS package. Determinate's docs do not say whether the existing `/nix/store` survives (**Unverified**), so everything installed through it, devbox global included, is treated as lost at that step.
- Later switches: `just switch`, which runs `darwin-rebuild switch --flake .#<host>` or `home-manager switch --flake .#<user>@wsl` with the recorded host.
- On `work-mac` the first `curl`, the Nix installer, and the clone in step 4 go through the corporate proxy before any Nix CA setting or `http.sslCAInfo` exists (the latter arrives with the work profile in step 7). Whether macOS' `curl`, Determinate's installer, and nixpkgs' git trust the corporate CA at that point is **Unverified**; test it on the corporate network before relying on the one command there.
- `justfile` defines exactly `switch`, `update`, and `check`.

## Corporate TLS interception

Each Nix network path reads certificates from a different place (checked against Nix 2.33.0 and nixpkgs 26.05pre source).

| Path | Examples | CA source | Action |
|---|---|---|---|
| Nix's own downloads | Substitution, `github:` inputs, `builtins.fetchurl` / `fetchTarball`, flake registry, git LFS | `ssl-cert-file`, read by both client and daemon | `ssl-cert-file` in `/etc/nix/nix.conf` |
| `builtin:fetchurl` | Bootstrap fetches | The daemon's `ssl-cert-file` | Same |
| nixpkgs `fetchurl` and npm dependencies (`prefetch-npm-deps`) with a real hash | Most source fetches | None: TLS verification is disabled because the hash verifies the content | Nothing |
| Build-time fetches (`fetchgit`, Go / cargo dependencies) | Fixed-output derivations | The daemon's `NIX_SSL_CERT_FILE`, passed through `impureEnvVars` | Set it in the daemon's environment. In the Linux sandbox only `/etc/ssl/certs/ca-certificates.crt` (a bind mount of `ssl-cert-file`) exists, so point the variable there. |
| Derivations that hard-code nixpkgs' cacert | `fetch-yarn-deps`, `buildBazelPackage`, `dockerTools`, `fetchrepoproject`, and `fetchurl` / `prefetch-npm-deps` with an empty or fake hash or a netrc | Fixed to nixpkgs' bundle | Cannot be fixed by configuration. Use only what the binary cache provides, and never build with a fake hash behind the proxy. |
| Git-based fetches | `git+https://` inputs, `builtins.fetchGit` | Runs the `git` binary, so the evaluating user's gitconfig applies (which user under `sudo` is **Unverified**) | Prefer `github:` inputs; otherwise `http.sslCAInfo` |
| `hg+https://` | Mercurial inputs | No CA passed to `hg` | Do not use |

- **Precedence**: the manual says `NIX_SSL_CERT_FILE` overrides `ssl-cert-file`, but in 2.33.0 the configured value wins (measured on upstream Nix 2.33.0; Determinate Nix is **Unverified**).
- Only `work-mac` is behind the corporate proxy, so this section applies to it alone.
- **Bundle**: use the system roots concatenated with the corporate CA, never the corporate CA alone.

**macOS (`work-mac`)**

- Determinate Nixd exports Keychain certificates at start-up. After the certificate store changes, restart Determinate Nixd.
- Determinate's nix-darwin module rejects `ssl-cert-file` in `customSettings` with an assertion.
- How nix-darwin's `security.pki` default `NIX_SSL_CERT_FILE` (`mkDefault "/etc/ssl/certs/ca-certificates.crt"`) interacts with this, and whether Determinate Nixd passes `NIX_SSL_CERT_FILE` to the daemon, are **Unverified**; test on the corporate network.

## CI

- `nix flake check` neither evaluates nor builds `darwinConfigurations` or `homeConfigurations` (measured), so build them explicitly:
  - macOS runner: `nix build .#darwinConfigurations.<host>.system`
  - Linux runner: `nix build .#homeConfigurations."<user>@wsl".activationPackage`
- `nix flake check` runs the formatter check and the hook builds (shellcheck included) ([ADR 0008](adr/0008-repo-checks-lefthook-treefmt.md)).
- Generate and check `settings.json` (work side from `profiles/work.example/`).
- Tests for hooks, skills, and scripts.
- gitleaks.
- No tracked path matches a `Read(...)` deny pattern in the common settings, so every file stays readable to the agents that maintain it. The check reads the patterns from the settings rather than a copied list.
- Shell tests, without a switch, on any runner and locally: a temporary `HOME` holds only this repository's `home/` files, and `env -i` starts `zsh -c`, `zsh -lc`, and an interactive zsh fed commands on stdin (`zsh -ic` runs no history or `preexec` hooks, measured). They check:
  - the four XDG variables, `ZDOTDIR`, and `ATUIN_HOME` take the expected defaults, and an `XDG_CONFIG_HOME` set by the caller is kept;
  - with stock `/etc` files, `.zprofile` puts Nix's directories ahead of `/usr/bin` in a login shell;
  - the interactive shell writes no history file and creates `$XDG_CACHE_HOME/zsh`;
  - after the shells exit, every entry in `$HOME` is on an allowlist, which catches a stray history, completion dump, rc file, or `~/.atuin`;
  - each variable repeated for launchd or `environment.d` equals its value in `$ZDOTDIR/.zshenv`.
- Package tests, on the built configuration and still without a switch: each build job evaluates its host's `pkgs` set and home-manager configuration, builds `home.path` and `home-files`, and checks that `home.packages` names exactly the attributes above plus the entries home-manager adds itself, that `allowUnfree` is false and the predicate admits `claude-code` and refuses every other name it is asked about (a prefix of `claude-code` and that name with a suffix among them), that every global tool is in the profile, that `env -i PATH=<profile>/bin:/usr/bin:/bin zsh -c 'command -v <tool>'` answers with the profile's copy rather than `/usr/bin`, that the profile PATH names serves that same profile (`/etc/profiles/per-user/<user>/bin` in the built system on macOS, the generation's `home-path` on `wsl`), that `~/.config/zsh` and `~/.config/mise` are real directories and that `~/.zshenv` and their entries resolve to `<home>/repos/github.com/paveg/dotfiles/home/<path>` in full, and that the global mise config refuses an `asdf:` tool with `mise settings get disable_backends` reading exactly `["asdf"]`. Every check has a mutant except the ones that guard the test harness itself and the `wsl` generation's own link to the profile. The per-user profile mutant runs in the macOS jobs, where that profile is built, and the host-independent ones on the Linux runner.
- Bootstrap tests run `scripts/bootstrap.sh` from the start with `DOTFILES_REF` set to the commit under test: `wsl` on a Linux runner as a newly created user with an empty home, and `personal-mac` and `work-mac` on a macOS runner, whose preinstalled Homebrew exercises `autoMigrate`. Whether a hosted macOS runner can run a nix-darwin switch is **Unverified**.
  - Human steps are stubbed by making each step's check pass, so the script's own logic runs unchanged:
    - 1Password on macOS: a real Unix socket listening at the agent socket path, so the check can stay `test -S`. On WSL2, where SSH goes through `ssh.exe`, a stub `ssh-add.exe` that lists one key.
    - 1Password sign-in for the `ghtkn.yaml` render in step 8: a stub whose `inject` writes the template with placeholder client IDs, named `op` on macOS and `op.exe` on WSL2, matching the binary each host calls.
    - Keeper: `profiles/work.example/` placed in `~/.config/dots-work/` (the hand-placed path of step 7, so `ksm` is never called).
    - ghtkn: a stub `ghtkn` that exits 0.
  - Stubs live in `DOTFILES_TEST_STUB_DIR`, which only CI sets and which the script announces when set. The script puts it at the front of PATH after every PATH change, including after step 5, so a stub always wins over the real tool.
  - When a check fails and no terminal is attached, the script exits with a distinct status ("waiting for a person") instead of waiting for Enter, so CI fails rather than hangs.
  - They check:
    - a missing or mismatched host exits non-zero and changes nothing;
    - a run with one stub removed exits with the "waiting for a person" status, and resumes and finishes once the stub is back;
    - a second complete run changes nothing;
    - a login shell after the real switch resolves `git` from Nix;
    - `$HOME` gains no entry outside the allowlist: on Linux by listing the new user's home, on macOS by diffing the runner's home before and after.
- `git diff --check origin/main...HEAD`, the same check lefthook runs before a commit (the job checks out with `fetch-depth: 0`, since a shallow checkout has no `origin/main` merge base and the command would fail), so a commit made without lefthook installed still cannot merge leftover conflict markers.
- Every test is shown to fail on a deliberately broken subject (for example, the `ZDOTDIR` line removed, or the host check skipped), and that mutation run is part of CI.
- Not covered by CI: real 1Password, Keeper, and ghtkn authentication, Orca, `scripts/unattended-setup.sh` and Tailscale, the corporate proxy, and a real user's WSL2 setup (the Windows-side apps and the Windows PATH of that machine); the `windows-2025` job below covers WSL2 itself only as far as it states. The monthly run covers the bootstrap; `scripts/unattended-setup.sh` and Tailscale are covered only by the manual acceptance criterion for the unattended host.
- Templates: each flake template is instantiated and checked (see Project layer).
- `.github/workflows/spec.yml` runs `spec/check.sh`: TLC on each model, and on one mutant per property that must fail on that property (see Formal models).
- Windows runner: the `wsl` bootstrap test also runs on `windows-2025`, whose image lists "Windows Subsystem for Linux (Default, WSLv2)", in an Ubuntu distro installed by `Vampire/setup-wsl` (the image has no distro; the action defaults to WSL 2 and its `wsl-conf` input writes `/etc/wsl.conf`, which is used to set `[boot] systemd=true`). If systemd is still not running, step 2 stops as the Bootstrap section says, and the job fails: that is a defect in the job to fix, not an expected stop. A separate step runs `ssh.exe -V` from the distro to check interop, because the bootstrap never exercises it in CI: step 4 clones over HTTPS, and step 6's check uses a stub `ssh-add.exe`. Whether the `wsl-conf` route brings up systemd on a hosted runner, and whether the image ships an `ssh.exe`, are **Unverified**. The image's software list has no winget, so the Windows-side installs are not tested in CI.
- Monthly: run the bootstrap on a fresh macOS user account or Linux VM.
- Weekly: `DeterminateSystems/update-flake-lock` opens a pull request that updates `flake.lock`. A pull request opened with the default `GITHUB_TOKEN` does not trigger CI (the action's README), while one opened with a GitHub App token triggers `push` and `pull_request` workflows (peter-evans/create-pull-request, which the action uses), so the workflow mints a token with `actions/create-github-app-token` from a GitHub App made for this job alone: installed only on this repository, with Contents and Pull requests write and nothing else beyond the Metadata read that every App has. Its App ID and private key are repository secrets. The private key is long-lived, but it can mint tokens only for this repository and only with those two permissions.
- Dependabot updates GitHub Actions versions (`github-actions` ecosystem only).

## Acceptance criteria

- [ ] A fresh macOS / WSL2 machine is ready after one bootstrap command (first-time 1Password, Keeper, and ghtkn authentication, App Management for the switching terminals, Karabiner's approvals, Raycast's script directory, the Windows-side Windows Terminal, Orca, 1Password, 1Password CLI, and Raycast installs for `wsl`, and the Raycast import excepted; `personal-mac`'s unattended setup is a separate, manual step)
- [ ] The bootstrap without a host, or with a host other than the recorded one, exits non-zero and changes nothing
- [ ] On `personal-mac` and `wsl`, the bootstrap never runs `ksm` and `~/.config/dots-work/` does not exist afterwards
- [ ] Running the bootstrap again after it stopped at a human step resumes and finishes
- [ ] In a login shell (`zsh -lc`), `command -v git` prints a Nix path, not `/usr/bin/git`
- [ ] After a fresh bootstrap and one interactive shell, `$HOME` holds only allowlisted entries, history lands in atuin under `$XDG_DATA_HOME/atuin`, and no zsh history file exists
- [ ] A command containing a `ghu_` token, and one assigning `FOO_TOKEN=…`, typed in an interactive shell are absent from atuin, and atuin makes no request to `api.atuin.sh`
- [ ] `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -c 'command -v gh ghq fzf rg'` succeeds on every host, and each path it prints is under a Nix profile (today it passes only through devbox global, measured)
- [ ] A project tool installed with the project layer's default resolves from `zsh -c` inside that project
- [ ] Orca sees `gh` and can show PRs; record whether Orca starts zsh
- [ ] Claude Code can use `gh` and `git`, and standard commands print unmodified output
- [ ] `gh` in a non-interactive shell works with a ghtkn token, and `~/.config/gh/hosts.yml` holds no token
- [ ] `gh` uses the work app on `work-mac` and the personal app on `personal-mac`; neither host has the other's `ghtkn.yaml`
- [ ] On `work-mac`, HTTPS push to a work repository succeeds through `ghtkn git-credential`, and push to a personal repository succeeds over SSH
- [ ] Repositories under `~/repos/github.com/<work-gh-org>/` (including linked worktrees) use the work identity; all others use the personal one
- [ ] On `work-mac`, `zsh -c 'echo $AQUA_GHTKN_ENABLED'` prints `true`
- [ ] `~/.claude/settings.json` on `work-mac` contains the work plugins and internal endpoint; on `personal-mac` it does not
- [ ] With 1Password locked, an SSH `git fetch` and a signed commit go through with Touch ID alone
- [ ] On `personal-mac`, after `scripts/unattended-setup.sh`: with the phone off the home LAN and on the tailnet, Orca Mobile reaches the host, Tailscale SSH opens a shell on it, and running the script again changes nothing
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

- Commits made while the host is unattended start unsigned and are re-signed at the desk before a pull request (ADR 0005's fallback). If waiting for the desk becomes the bottleneck, the next step is a dedicated signing-only key in the Secure Enclave (Secretive), registered on GitHub as a signing key only (ADR 0005). Whether it signs while the screen is locked is **Unverified** and is measured before adopting it. Commits through GitHub's API are not pursued. GraphQL `createCommitOnBranch` is signed by GitHub "if supported" even under a user token, but it replaces `git commit`: the agent sends file contents to the API instead of committing locally, so local git hooks do not run (ADR 0005).
- Secrets that agents need while the host is unattended: a 1Password service account (`OP_SERVICE_ACCOUNT_TOKEN`) reads only custom vaults, never Personal, Private, or Employee, and its token then lives on the host.
- Whether to enable the Bash sandbox by default, after measuring the sockets and network calls it must allow.
- Whether to auto-start a terminal multiplexer (tmux / herdr) in interactive shells at all.
- Whether Keeper Secrets Manager is available at work (ask IT).
- 1Password auto-lock timeout.
- How to run the ghtkn agent on WSL2.
- Where Orca creates its worktrees, and whether that location needs its own ignore entry.

## Rollout

1. Create this repository with the minimum: flake, `.zshenv`, `.zshrc`, git, ssh, `~/.claude`. Create the personal GitHub App for ghtkn. Create the lock-update GitHub App described in CI and store its secrets.
2. Switch `personal-mac`. Remove the Tailscale GUI app first (it is installed today), so that the only `tailscaled` is the open-source one nix-darwin runs (ADR 0010). It runs upstream Nix with devbox global on top, so first list what devbox global provides (today it supplies `gh`, `ghq`, `fzf`, `rg`, gitleaks, kubectl, helm, aqua, and just, measured) and confirm each one has a home in the Packages section (aqua goes to `work-mac` only, `gh` becomes the wrapper), judged by P6, then switch to Determinate Nix and run the first switch. devbox global is gone from this point.
3. Run it for one to two weeks; pull in from the old repository only what is missed, judged by P6.
4. Roll out to WSL2 (enable systemd first).
5. Roll out to `work-mac`: set up KSM, pull the work profile, verify CA handling.
6. Archive the old repository. Decide first what to do about the company settings in its history.
