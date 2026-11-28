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
| P8 | Nix for tools, casks for macOS apps | A tool that is not a macOS GUI app comes from a nix-darwin or home-manager module, then a nixpkgs package, then a manual install. A global CLI tool comes from a language package manager (`uv tool install`, `cargo install`, `go install`, `pnpm add -g`, `npm -g`, `gem install`) only when nixpkgs lacks it, and that install gets an `outsideNix` entry in `nix/licenses.nix`. A macOS GUI app comes from a Homebrew cask through nix-homebrew, then a nixpkgs package, then a manual install. Each tool on a later rung names why the earlier ones do not work ([ADR 0014](adr/0014-tool-sources.md)). |

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

- Nix installs no language runtime, only the version managers `mise`, `uv`, `rustup`, and `elan` ([ADR 0012](adr/0012-language-runtimes-from-version-managers.md)). `home/.config/mise/config.toml` holds global defaults for Go, Node, pnpm, Deno, and Ruby, which a project's `mise.toml` overrides; `.node-version`, `.nvmrc` and `.ruby-version` are not read. Python runs through `uv run`, with no `python3` from Nix on PATH. Swift comes from Xcode on macOS, and MoonBit from its official installer on `personal-mac` and `wsl` only.
- The default for new projects is **mise in shims mode** ([ADR 0006](adr/0006-project-layer-mise-shims.md)). The condition it meets: its tools resolve from `zsh -c` without a shell hook. `$ZDOTDIR/.zshenv` puts mise's shims directory (`$XDG_DATA_HOME/mise/shims`; mise uses `MISE_DATA_DIR`, else `XDG_DATA_HOME/mise`) on PATH, and nothing calls `mise activate`. Measured: with only the shims directory on PATH, a non-interactive `zsh -c` ran a project tool declared in `mise.toml`.
- mise tools come from the `aqua:` backend where one exists, never from asdf plugins, and projects commit `mise.lock` (ADR 0006). `home/.config/mise/config.toml` sets `disable_backends = ["asdf"]`, so every host refuses an `asdf:` tool with `backend asdf is disabled by disable_backends` before it fetches anything (measured). It is a host default rather than a lock: a project whose own `[settings]` sets `disable_backends` to something else gets that value, measured in a directory whose `mise.toml` set it to `[]`. `~/.config/mise/config.override.toml` beats a project's settings (measured) but would leave a project that needs an asdf tool no way out, so the overridable default stands.
- Hook-activated environments (direnv, `mise activate`) are not used, because a plain `zsh -c` never sees them.
- Existing projects keep what they use (devbox, a flake devShell). Agents then run commands through `devbox run` / `nix develop -c`, which the project's own CLAUDE.md states.
- Repositories that pin tools in `.aqua.yaml` use aqua, whose bin directory `.zshenv` also puts on PATH.
- Formal-methods tools are project tools, not global packages: their versions belong to the project that uses them. The flake ships `templates` so that a new project gets them in one command ([ADR 0006](adr/0006-project-layer-mise-shims.md)):
  - `nix flake init -t github:paveg/dotfiles#tlaplus`: a flake with a devShell holding nixpkgs' `tlaplus18` (TLA+ tools 1.8.0, which installs `tlc`, `tlasany`, `pcal`, `tlatex`, and `tlarepl`), a small specification `Spec.tla` with its model config `Spec.cfg` (TLC picks up `<Module>.cfg` beside the module, measured), a CI workflow that runs `nix develop -c tlc Spec.tla` on it, and an `AGENTS.md` that tells agents to run the checker that way.
  - `nix flake init -t github:paveg/dotfiles#lean`: a flake with a devShell holding `elan`, plus a `lean-toolchain` file and a minimal Lake project. Lean projects pin their toolchain in `lean-toolchain`, and libraries such as Mathlib follow it, so `elan` installs the toolchain the file names rather than nixpkgs' single `lean4` version. `elan` is also a global package ([ADR 0012](adr/0012-language-runtimes-from-version-managers.md)), and that copy uses elan's default `~/.elan`, not the template's `ELAN_HOME`. The devShell sets `ELAN_HOME` to `${XDG_DATA_HOME:-$HOME/.local/share}/elan` in its `shellHook`, because elan's default is `~/.elan` (elan reads `ELAN_HOME`, `src/elan-utils/src/utils.rs`). `nix develop -c` runs `shellHook` on upstream Nix 2.33.0 (measured by a review agent); on Determinate Nix the template test decides it. On Linux, nixpkgs' elan patches each toolchain it downloads to use the store's dynamic linker, shell, and C compiler (`0001-dynamically-patchelf-binaries.patch`). Those toolchains live outside the store and are not garbage-collection roots, so a `nix store gc` after a `flake.lock` update may break an installed toolchain; reinstalling it with `elan` repairs it. This is inferred from the source, not run.
  - CI instantiates each template in a temporary directory and runs its own check (`tlc` on the sample specification, `lake build` on the sample project), so a template that no longer works fails here, not in a new project.

### Rejected

| Candidate | Reason |
|---|---|
| chezmoi | Overlaps with home-manager's file placement. |
| devbox global | Cannot manage casks; no clear lock. |
| home-manager `programs.*` | Generated config is hard for agents to read. Exception: shell integration that has no other form. |
| Direct `brew install` | Casks only through nix-darwin. |
| zinit, powerlevel10k, starship | Agents never see the prompt. Plain zsh prompt, and the two plugins come from nixpkgs, so no plugin manager is needed. |
| zsh-abbr | Its `LICENSE` is CC BY-NC-SA 4.0 combined with the Hippocratic License 3.0: a non-commercial licence, and `work-mac` is a work machine. A table and a short widget in `.zshrc` do the same. |
| nix-darwin's `programs.zsh.enableAutosuggestions` / `enableSyntaxHighlighting` | They exist on macOS only, and `wsl` sources the same plugins from its profile anyway. |
| The global `compinit` (nix-darwin's `enableCompletion`, Ubuntu's `/etc/zsh/zshrc`) | It runs before `.zshrc` has put the profiles' completions on `fpath`, and with no `-d` its dump goes to `${ZDOTDIR:-$HOME}/.zcompdump` (zsh 5.9's `compinit`, line 133). |
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
│   ├── agents.nix            # hook builds and the settings.json generator (claude-settings.sh)
│   ├── agents-home.nix       # ~/.claude and ~/.codex wiring: links, the settings.json activation
│   ├── claude-settings.sh    # the generator's script
│   ├── orca-hooks.json       # the copy of Orca's 16 hook entries the generator writes
│   ├── licenses.nix          # licences nixpkgs cannot give: generated derivations, installs from outside Nix
│   ├── ssh_config            # ~/.ssh/config on macOS, copied into the store, not linked
│   ├── ghtkn.nix             # builds of the gh wrapper (gh.sh) and the ghtkn.yaml render step (ghtkn-render.sh)
│   └── vaults.nix            # 1Password, Keeper, ghtkn wiring (today ghtkn only)
├── home/
│   ├── .zshenv               # sets ZDOTDIR and sources the real one
│   ├── .config/zsh/{.zshenv,.zprofile,.zshrc}
│   ├── .config/atuin/config.toml
│   ├── .config/mise/config.toml  # global settings and runtime defaults; refuses the asdf backend
│   ├── .config/git/{config,ignore,personal.gitconfig,darwin.gitconfig,wsl.gitconfig}
│   ├── .config/ghtkn/{ghtkn.personal.yaml.tpl,gh-app.personal}
│   ├── .config/1Password/ssh/agent.toml
│   ├── .config/{nvim,ghostty}/
│   ├── .config/karabiner/        # linked as a directory; automatic_backups/ ignored
│   ├── .config/raycast/scripts/  # Raycast Script Commands
│   ├── .claude/              # CLAUDE.md, rules/, agents/, references/, hooks/ (sources), settings.{common,personal}.json
│   ├── .codex/               # config.toml source (written as a regular file at activation)
│   └── .local/bin/
├── profiles/work.example/    # shape of the work profile, placeholder values, no company values, used by CI (claude/settings.work.json, git/, ghtkn/ and env/static.env so far)
├── tests/
├── scripts/{bootstrap.sh,work-sync.sh,unattended-setup.sh,pre-wipe-inventory.sh}
├── templates/{tlaplus,lean}/  # flake templates for formal-methods projects
├── spec/                     # TLA+ models and check.sh (TLC plus one mutant per property)
├── docs/
├── .github/{workflows/,dependabot.yml}
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
- `$ZDOTDIR/.zshenv` (every shell): PATH (Nix profiles, `/etc/profiles/per-user/$USERNAME/bin`, `~/.local/bin`, mise shims, aqua's bin directory), `LANG`, `EDITOR`, `VISUAL` (`nvim`), `PAGER` (`less`), `MANPAGER` (`less -R`), `KUBECONFIG` (below), `skip_global_compinit` (below), and `~/.config/dots-work/env/static.env` if it exists. No secrets.
  - `LANG` is `en_US.UTF-8` where libc can load it, else `C.UTF-8`. A stock Ubuntu is expected to have only the latter, and a `LANG` the system lacks makes child processes warn (both **Unverified** on `wsl`). `LC_ALL` stays unset, and a `LANG` the caller set is replaced, as the old setup did. `.zshenv` asks libc in-process, because every `zsh -c` pays for the answer: in a function scope it sets `LC_ALL` to `C` and then to `en_US.UTF-8`, each of which makes zsh call `setlocale`, and reads the codeset through `zsh/langinfo`; `setlocale` keeps the locale it had for a name it cannot load. `locale -a | grep` cost two processes, 2.3 ms more than main on each `zsh -c true` on this Mac, and this costs 0.2 to 0.7 ms more (measured). Testing for the locale directories would cost nothing, but glibc's `locale-gen` writes into `/usr/lib/locale/locale-archive`, not a directory per locale (**Unverified**: not measured on Ubuntu).
  - `KUBECONFIG` lists `~/.kube/config` and then each `~/.kube/*.yaml`, those that are files or symlinks to one, joined with `:`, so kubectl merges the contexts of every file (measured: kubectl 1.37.2). A path that holds a `:` is left out, so a `HOME` with a `:` in it leaves the whole list out and kubectl reads `config` alone (measured): kubectl splits the list on `:`, and with `~/.kube/team:prod.yaml` listed it read a `prod.yaml` in the working directory (measured). A known cost: one `*.yaml` kubectl cannot load fails every kubectl command, where without the variable kubectl reads only `config`: with an unreadable file, malformed YAML, or a `Deployment` manifest listed, `kubectl config get-contexts` exited 1 with `error loading config file`, and an empty file loaded (measured). With none of them, including when `~/.kube` does not exist, it is not exported, and kubectl reads `~/.kube/config` as it would anyway. A non-empty value the caller set is kept: every nested `zsh -c` runs `.zshenv`, so replacing it would undo a cluster chosen for one session or one command. The cost is that a shell started before a new file appeared hands its children the old list. A missing `config` is left out rather than listed first, which changes nothing for writes: with a missing `config` listed first, `kubectl config set-context` wrote to the next file (measured). The list comes from globs in a function scope, with no subprocess; on this Mac they cost about 0.5 ms per `zsh -c true` when `~/.kube` exists and nothing measurable when it does not (measured). The files stay in `~/.kube`, so the `Read(~/.kube/**)` rule covers them unchanged.
  - Login shells: macOS's `/etc/zprofile` runs `path_helper`, which runs after `~/.zshenv` and moves the system directories to the front of PATH. Measured in a temporary `HOME` on this Mac (no nix-darwin): the first PATH entry set in `.zshenv` stayed first under `zsh -c` and became `/usr/local/bin` under `zsh -lc`, so `/usr/bin/git` would win over Nix's. `$ZDOTDIR/.zprofile`, read after `/etc/zprofile`, therefore puts the same directories back in front. A review agent read nix-darwin's `modules/programs/zsh/default.nix`: with `programs.zsh.enable` (default `true`) it generates `/etc/zprofile` with no `path_helper` call. Whether that replaces Apple's file on a given host is **Unverified**, so `.zprofile` keeps the fix either way, and the bootstrap tests check login-shell PATH after a real switch.
  - nix-darwin's `/etc/zshenv` adds `/etc/profiles/per-user/$USER/bin`, and `$USER` is a literal expanded at run time. Under `env -i` zsh leaves `USER` empty but still sets `USERNAME` and `LOGNAME` (measured), so that entry becomes `/etc/profiles/per-user//bin`. The `$USERNAME` entry above covers it.
- Environment variables are written by hand in plain files, not generated from one Nix source (ADR 0001). A variable that a process started without zsh also needs (a GUI app, the ghtkn agent) is repeated in `launchd.user.envVariables` on macOS or `~/.config/environment.d/` on WSL2, and a CI test checks that each repeated value equals the one in `$ZDOTDIR/.zshenv`. Variables left at their spec defaults need no repetition.
- XDG policy: a tool that already follows the XDG variables needs nothing. A tool that needs its own variable to move (for example `CLOUDSDK_CONFIG`, `DOCKER_CONFIG`) gets it in `$ZDOTDIR/.zshenv`, and only after its support is checked; each tool's support is **Unverified** until then. Two limits apply. A process that does not start through zsh never sees these variables, which is why the defaults are the spec defaults. A moved credential path must also move in the `permissions.deny` `Read(...)` rules; a CI test compares the paths exported in `$ZDOTDIR/.zshenv` with those rules, so the two cannot drift.
- Expected not to move (both **Unverified**): `~/.ssh`, which OpenSSH reads from the home directory, and git include paths, which expand `~` but not environment variables. `~/.claude` and `~/.codex` stay where they are until `CLAUDE_CONFIG_DIR` / `CODEX_HOME` are shown to reach Orca-launched agents.
- `$ZDOTDIR/.zshrc` (interactive only, so `zsh -c` sees none of it): keymap, options, completion, key bindings, plugins, abbreviations, plain prompt. Sources `$ZDOTDIR/.zshrc.local` (untracked, non-secret local settings) if present, last. The zsh files are linked one by one, so `~/.config/zsh` is a real directory and `.zshrc.local` stays outside the checkout; `.gitignore` also lists it. A setting worth keeping moves into the repository.
- zsh keeps history in memory only (`SAVEHIST=0`, `HISTFILE` unset), so up-arrow works within a session and atuin is the only history on disk. A zsh history file would bypass every filter atuin applies. Both settings are made in `.zshrc`, because macOS's `/etc/zshrc` sets `HISTFILE` after `.zshenv` runs.
- `.zshrc` creates `$XDG_CACHE_HOME/zsh` when it is missing, so a fresh machine needs no switch step for it. zsh does not create the parent directory of a file it writes; for a history file it prints `locking failed … no such file or directory` at exit and saves nothing (measured).
- Keymap: `bindkey -e`, before any other binding. zsh starts in the vi keymap when `EDITOR` or `VISUAL` contains `vi`, so `EDITOR=nvim` alone took Ctrl+a, Ctrl+e and Ctrl+k away (measured: `bindkey -lL main` printed `bindkey -A viins main`).
- Options: `INTERACTIVE_COMMENTS`, `AUTO_CD`, `AUTO_PUSHD`, `PUSHD_IGNORE_DUPS`, `NO_BEEP`, and `HIST_IGNORE_DUPS`, which acts on the in-memory history only.
- Completion: one `compinit`, in `.zshrc`, with its dump and cache under `$XDG_CACHE_HOME/zsh`, after `.zshrc` has put `share/zsh/site-functions` of each Nix profile on `fpath` (the profiles are the parents of the PATH entries `$ZDOTDIR/.zshenv` adds). That is where packages put their completions; a stub in a fake profile stands in for them in `tests/shell.sh`, and `tests/packages.sh` checks that the built profile completes `gh` with its `_gh`, which the wrapper links from nixpkgs' `gh`. zstyles: menu selection, lowercase matching uppercase, and the completion cache.
  - The global calls are off, so this is the only one. nix-darwin sets `programs.zsh.enableCompletion` and `enableBashCompletion` to false and `promptInit` to empty: by default its `/etc/zshrc` runs `compinit`, `bashcompinit`, and `prompt suse` before `.zshrc` (measured in the built system, and `tests/packages.sh` checks the built file). Ubuntu's `/etc/zsh/zshrc` runs `compinit` unless `skip_global_compinit` is set, which `$ZDOTDIR/.zshenv` does.
  - nix-darwin's `/etc/zshenv` puts the `site-functions` of each profile in `NIX_PROFILES` on `fpath` whatever these options say, so on a switched mac those directories appear on `fpath` twice.
- Key bindings: `Ctrl+g` for ghq + fzf; fzf's own bindings from `fzf --zsh`, `Ctrl+t` for files with a bat preview and `Alt+c` for directories with an eza tree, both listed by fd (hidden files included, `.git` excluded), with Tokyo Night colours in `FZF_DEFAULT_OPTS`; then atuin's, so `Ctrl+r` is atuin's, since fzf's script binds it too (measured: fzf 0.75.0). zoxide's `z` is loaded too.
  - fzf's bindings load only when the shell has a terminal (`$TTY` is set). Its script restores every option on the way out, `zle` included, and a `zsh -i` with no terminal refuses that: `zsh -i -c 'echo hi' </dev/null` printed `(eval):1: can't change option: zle` twice on stderr (measured). The `zle` option itself reads on while `.zshrc` runs in such a shell, so it cannot be the test.
- Plugins: zsh-autosuggestions and zsh-syntax-highlighting from nixpkgs, with no plugin manager, sourced from the first profile on PATH that has them. Their order does not matter on zsh 5.9: zsh-syntax-highlighting 0.8.0 draws from a `zle-line-pre-redraw` hook there and wraps no widget, and zsh-autosuggestions 0.7.1 binds its widgets at the first prompt, after both have loaded (measured: the same widget table in either order). nix-darwin's per-user profile links only `environment.pathsToLink` (`modules/users/default.nix`), which leaves out `share/zsh-syntax-highlighting`, the only place that package puts its script (measured), so `nix/darwin.nix` adds both plugin directories and `tests/packages.sh` checks the files in the profile that PATH names.
- Terminal: `TERM` falls back to `xterm-256color` when the host has no terminfo for Ghostty's `xterm-ghostty` (a host reached over SSH), and inside tmux to `screen-256color` when it has none for the `TERM` tmux set. Mouse reporting left on by a program that died is turned off at the first prompt, when stdout is a terminal, so `printf 'echo hi\n' | zsh -i` prints only `hi` on stdout (`tests/shell.sh` checks it).
- Aliases: none. Short forms are abbreviations instead: a table and a widget in `.zshrc` expand a name typed as the whole command line when Space or Enter is pressed, so the full command is what runs and what atuin records. Only at the primary prompt with nothing right of the cursor: zle's `CONTEXT` is `start` there, and `cont` on a line inside an open quote or a heredoc, `vared` in `vared` (measured under a pty), so `g` typed before `it status` stays `g`. The names are `g` and the git forms from the old setup (`gst` for `git status`, `gco` for `git checkout`, and so on), `k` (kubectl), `lg` (lazygit), `v` (nvim), `ll` (`eza -l --git`), `la` (`eza -la --git`), `lt` (`eza --tree --level=2`), and `b` (bat). Every name shadows nothing: `vi`, `vim`, and `gs` (Ghostscript) are left out, and `tests/shell.sh` fails if a name is a command on its PATH, which holds a stub for each command `tests/packages.sh` requires of the Nix profile.
- The keymap, options, key bindings, plugins, and abbreviations are desk conveniences: none reaches a process without an interactive shell, so like Karabiner-Elements they are a stated exception to P6.

### Shell history (atuin)

See [ADR 0009](adr/0009-shell-history-atuin.md). `$ZDOTDIR/.zshenv` sets `ATUIN_HOME=$XDG_DATA_HOME/atuin`: atuin's default home is `~/.atuin`, and it uses `XDG_DATA_HOME` only as a fallback for older installs (`crates/atuin-common/src/dirs.rs`), so without the variable a fresh machine gets a new entry in `$HOME`. With `ATUIN_HOME` set, atuin 18.24.8 reads, and on first run creates, `$ATUIN_HOME/config.toml` and never looks in `$XDG_CONFIG_HOME/atuin` (measured with `atuin info`; source: `config_path` in `crates/atuin-common/src/dirs.rs`), so `$ZDOTDIR/.zshenv` also exports `ATUIN_CONFIG_DIR=$XDG_CONFIG_HOME/atuin`, where the linked `config.toml` is. Besides layer 4 below, that file sets the old setup's interface: fuzzy search, the global filter, the compact inverted style, and `exit_mode = "return-query"`. atuin records interactive commands in SQLite with directory, exit code, duration, and session, so the history can be analysed for repeated or failing steps. Commands that agents run through `zsh -c` are not recorded, because atuin's zsh integration uses `preexec` / `precmd` / `zshaddhistory` hooks that do not fire in a non-interactive shell (measured by a review agent). The history holds human operations only; agent behaviour is analysed from session transcripts instead. atuin's opt-in agent hooks (`atuin hook claude-code`, `atuin hook codex`) are not installed.

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
- `nix/darwin.nix` sets `launchd.user.envVariables` to `ORCA_TELEMETRY_DISABLED=1` and `HOMEBREW_NO_ANALYTICS=1`, so apps started by launchd get them without a shell. The built system's `activate` runs `sudo --user=<user> -- launchctl setenv <name> '1'` for each (measured), and `tests/packages.sh` checks those lines. Neither is in `$ZDOTDIR/.zshenv` yet, so the equality check the Shell section requires for repeated variables has nothing to compare (see Open questions).

### Git

```gitconfig
# home/.config/git/config
[ghq]
  root = ~/repos
[core]
  excludesFile = ~/.config/git/ignore
[gpg]
  format = ssh
[commit]
  gpgsign = true
[include]
  path = ~/.config/git/personal.gitconfig      # name, email, user.signingkey
[include]
  path = ~/.config/git/platform.gitconfig      # the 1Password signer for the OS
[include]
  path = ~/.config/dots-work/git/include.gitconfig   # absent on personal hosts; git ignores it
```

```gitconfig
# ~/.config/dots-work/git/include.gitconfig (work profile, not in this repository)
[includeIf "gitdir/i:github.com/<work-gh-org>/"]
  path = ~/.config/dots-work/git/work.gitconfig

# ~/.config/dots-work/git/work.gitconfig (work profile)
[user]
  name = <work name>
  email = <work email>
  signingkey = ssh-ed25519 <public half of the work signing key in 1Password>
```

- Identity switches per directory with `includeIf`. Later includes win, so the work profile's include comes last. Linked worktrees created from a work repository also get the work identity (measured): `gitdir:` matches the repository's git directory, and a linked worktree's is `<main checkout>/.git/worktrees/<name>`, inside the org directory wherever the worktree itself sits. For the same reason a personal repository's worktree placed inside the org directory stays personal (measured). `onbranch:` matches the checked-out branch's name, not where a repository lives, so it cannot express this.
- The condition is `gitdir/i:`, which ignores case: ghq keeps the clone URL's case, so `github.com/<Work-Gh-Org>/app` lands in a directory the lowercase pattern would miss, and a plain `gitdir:` then gave the personal identity (measured). On Linux, where the file system keeps case, two org directories that differ only in case both match; GitHub org names ignore case (measured), so both hold the same org's repositories and the work identity is right for both.
- The pattern does not start with `~/`, so git prepends `**/` and matches `github.com/<work-gh-org>/` anywhere in the git directory's path. git compares the physical path, and the path PWD names only when PWD is set; `git -C` and `env -i` leave PWD pointing elsewhere or unset, so a pattern anchored at `~/repos` missed every work repository when `~/repos` is a symlink (measured). A repository elsewhere whose path holds `github.com/<work-gh-org>/` is a clone of the work org, so it also gets the work identity.
- Limits, measured: when the org directory itself, or a work repository inside it, is a symlink to a path without `github.com/<work-gh-org>/`, `git -C` and a run without PWD give the personal identity. The real `include.gitconfig` then needs a second `includeIf "gitdir/i:<physical path the symlink points to>/"` with the same `path`: the org directory's for a symlinked org directory, the repository's for a symlinked repository. Each fixed its case in every reading (measured); an include on the org directory's physical path does not help a repository symlinked from elsewhere. A personal repository symlinked into the org directory gets the work identity when PWD names the link, and a work repository checked out as a submodule of a personal one gets the personal identity, because its git directory sits in the personal repository's `.git/modules/`.
- The `includeIf` names the GitHub org directory, so it lives in the work profile, not here. `profiles/work.example/git/` holds its shape with placeholder values (`example-org`, `work@example.com`); `tests/git.sh` places it where `work-mac` keeps the real one.
- Commits are signed with an SSH key held in 1Password ([ADR 0005](adr/0005-commit-signing.md)): `gpg.format ssh`, `commit.gpgsign true`, and `user.signingkey` set to the public key itself, which 1Password matches to the private key it keeps, so no key file is read from disk. The signer differs by OS, so `nix/home.nix` links `home/.config/git/darwin.gitconfig` or `wsl.gitconfig` to `~/.config/git/platform.gitconfig` (see 1Password agent). The work profile sets its own `user.signingkey`, the public half of the work signing key that 1Password holds; `profiles/work.example/` holds a marked placeholder in its place, and the real key and org name stay in the untracked profile. Without it a work commit is signed with the personal key, which GitHub shows as Unverified when the work email belongs to another account; `tests/git.sh` fails on a work profile that sets none.
- `gpg.ssh.allowedSignersFile` is not set, so a local `git log --show-signature` cannot verify a signature; GitHub verifies against the keys registered on each account.
- The global ignore lists `.claude/worktrees/` only.
- Tests (`tests/git.sh`, CI on Linux and macOS): in a temporary `HOME` holding the files under the names `nix/home.nix` links them to, with `GIT_CONFIG_NOSYSTEM=1`, a work repository, its worktrees inside and outside the org directory, a work repository under an org directory spelled in other case, one under a symlinked `~/repos`, a personal repository, a personal worktree inside the org directory, and a host without the work profile each resolve the expected name, email, and signing key, read from the directory and through `git -C` from `HOME`, each with PWD set as a shell sets it and without; the temporary `HOME` is its physical path, as a real one is. Each OS's file gives the signing settings a commit would use; nothing is signed. `tests/packages.sh` checks which file the built configuration links. `tests/mutate-git.sh` breaks one include, condition, or setting at a time.
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

`nix/agents-home.nix` lists `common` plus the host's profile with `builtins.readDir` and links each skill flat into `~/.claude/skills/<name>`. There is no exclusion list. A name present in two profiles is an evaluation error.

Pure evaluation cannot read `~/.config/dots-work/` (absolute paths outside the flake are forbidden, measured), so work-profile skills are linked by an activation script instead. That script also fails on a name that already exists in `~/.claude/skills/`.

**Generated `settings.json`.**

- Activation deep-merges `settings.common.json` with the profile's JSON (`settings.personal.json` in this repository, or `~/.config/dots-work/claude/settings.work.json`) using jq, and writes `~/.claude/settings.json` as a regular file of mode 600; a file whose content is unchanged is set to mode 600 too. If the work file is missing, the common file is used alone and activation warns. Each host file names its profile (`profile = "personal"` or `"work"`), and `home.activation.claudeSettings` (`nix/agents-home.nix`, after `writeBoundary`) runs `claude-settings settings <profile> <home>`; the script is `nix/claude-settings.sh`, built by `nix/agents.nix` with `writeShellApplication` and `inheritPath = false`. The file it replaces is read only to list what changes, and a link there is replaced by a regular file, leaving its target alone.
- On a personal host only, the generator merges `~/.config/dotfiles/claude/settings.local.json` last, when it exists. It is untracked and holds values this public repository must not, such as a collector's address. Claude Code telemetry is off unless that file turns it on: `settings.personal.json` carries only the exporter shape (`OTEL_SERVICE_NAME`, the metrics, logs, and traces exporters, and the two `OTEL_METRICS_INCLUDE_*` choices from the previous setup), and no `CLAUDE_CODE_ENABLE_TELEMETRY`, no `OTEL_EXPORTER_*` endpoint or protocol, and none of `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_TOOL_DETAILS`. A host without the file sends nothing, and the work side never reads it. The previous setup's `OTEL_RESOURCE_ATTRIBUTES` took `host.name` from a shell expansion, which a `settings.json` value does not get, so it is left to the local file too.
- Not a store symlink: Claude Code writes to `settings.json` (installing a plugin at user scope adds it to `enabledPlugins`). Claude Code's docs say that when the file is generated or read-only, such a change lasts only for the current session.
- Changes made inside Claude Code are overwritten by the next switch. The switch first prints a line for each path the generated file adds, removes, or changes against the current one (`added: env.DB_PASSWORD`, `changed: hooks.PreToolUse[0].hooks[0].command`), and no value from either side, whatever its key is called. A current file that does not parse is named with `(not valid JSON, so not shown)`.
- Orca also writes this file. At app start (and when its hook setting changes) it merges 16 hook entries whose command runs `~/.orca/agent-hooks/claude-hook.sh`, keeping every other key, and backs the old file up to `settings.json.bak`. Those entries carry agent status to Orca and let Orca answer `PreToolUse` and `PermissionRequest` (that the iOS app relays those answers is **Unverified**). Orca does not restore them until it restarts.
- Orca reads the whole file, merges, and renames a new file over it, with no lock and no check that the file is unchanged. Claude Code takes `settings.json.lock` and re-reads inside it, but neither Orca nor the generator takes that lock. So a write that lands between another writer's read and write is lost. TLC found both directions on the first design (below): a switch dropping Orca's entries, and Orca, from a read taken before the switch, dropping the guard hooks.
- The generator therefore writes Orca's 16 entries itself, from a copy kept in `nix/orca-hooks.json` (as Orca writes them, so the copy can be compared with a live file by `jq`), instead of carrying them over from the file it read, so a switch never drops them; a stale write by Claude Code or by Orca's own theme sync still can. When Orca changes its entries, the switch lists the paths that differ, assuming the copy matches what Orca writes on that host (measured on one Mac only; what Windows Orca writes into the `wsl` file is **Unverified**). Orca rewrites its own version at its next start either way.
- On macOS the guard hooks and `permissions.deny` are also written to a managed-settings drop-in, `/Library/Application Support/ClaudeCode/managed-settings.d/50-dotfiles.json`. It holds the two guards and the merged `permissions.deny` (common plus profile), so the work deny rules are in it on `work-mac`, and nothing else: only the deny list is taken from the profile, which the user can edit and root reads, and a layer that would change the deny list's type fails the run before the drop-in is written (below). The reply-language checker stays out, because a broken checker in managed scope could not be turned off by the user. The switch writes the drop-in before `settings.json`; TLC shows the guards can drop out during the first switch if the order is reversed. The file is root-owned and world-readable, mode 644 (Claude Code skips a managed file it cannot read), so the agent cannot change it without sudo. nix-darwin's `system.activationScripts.extraActivation` writes it: the activation runs as root under `set -e`, and splices `extraActivation` before `postActivation`, where home-manager's darwin module runs the user's activation, so the drop-in comes first and a failure to write it stops the switch before `settings.json`. home-manager's run is also given the drop-in's path, and the generator writes nothing until the drop-in holds the guards, which mirrors `GenWrite`'s precondition in the model whatever order the activation takes.
- Claude Code merges hook entries and lists across settings levels, and runs a handler defined in two files once. A switch that changes a guard's store path can leave the old path in `settings.json` (a stale write by Orca) next to the new one in the drop-in; whether Claude Code then runs both is **Unverified**.
- The guards in the drop-in are protected only while it is the only writer of that file and Claude Code reads it. Claude Code uses only the highest-ranked managed source: when the employer delivers server-managed settings or an MDM profile on `work-mac`, the drop-in is ignored. Then only the copy in `settings.json` remains, and the race above can drop it until the next switch.
- On `wsl` no drop-in is written. Standalone home-manager runs as the user, so writing `/etc/claude-code/` would need a sudo step in the bootstrap unless the directory is writable by the user on that host (**Unverified**). Either way, Claude Code's docs call it user-writable on WSL, so a drop-in there would not keep the agent out. There the guards live only in `settings.json`, and the race above can drop them until the next switch.
- Only the guards move to managed settings. Other keys change behaviour there (a managed `enabledPlugins` entry cannot be turned off by the user, a managed `model` overrides a `/model` choice at each session start), so they stay in `settings.json`.
- The merge concatenates and de-duplicates arrays instead of using jq's plain `*`, which replaces them. Profiles need their own array entries: the work profile adds `permissions.deny` rules (cloud, cluster, and infrastructure CLIs) that must not apply to personal hosts. A layer that would replace an array or an object with another type (`permissions.deny` set to `null`, a string, or an object, or `permissions` set to `null`), or add a `permissions.deny` entry that is not a string, fails the run with the layer's name, and neither the drop-in nor `settings.json` is written. A layer that does not parse fails the same way. An empty deny list adds nothing, so a layer can add deny rules but not remove a common one.

**Permission rules.** `settings.common.json` writes its `permissions` rules to the forms below, because the inventory of the previous `~/.claude/settings.json` found each of these written another way:

- `Read(...)` rules for secrets outside a repository start with `~/` (for example `Read(~/.ssh/**)`, `Read(~/.aws/**)`, `Read(~/.kube/**)`). A pattern with no leading `/`, `~/` or `//`, such as `Read(id_rsa)` or `Read(**/*credential*)`, covers only the current directory and below, so it never reaches the home directory while the agent works in a repository.
- A Bash prefix rule ends in a space before the wildcard (`Bash(gh *)`). Without it, `Bash(gh*)` also matches `ghq`, and `Bash(go*)` matches `gopass`.
- `allow` holds no database client and no command whose subcommands include a destructive one (`gh pr merge`, `gh repo delete`, `gh release delete`). Auto mode's classifier decides those (below), and the database guard and the classifier decide a client.
- `git reset` and `git rebase` are `ask`, not `deny`. They are routine on a feature branch, but `git reset --hard` discards uncommitted work that no reflog holds, so a person confirms each. An `ask` rule with a command pattern still prompts in auto mode.
- A `deny` or `ask` prefix rule matches the order Claude usually writes, not every spelling (`Bash(git push --force *)` misses `git push origin main --force`). What must hold whatever the spelling is enforced elsewhere: branch protection on GitHub, the sandbox, or a guard hook.
- `Edit(~/.claude/settings.json)` and `Edit(~/.claude/hooks/**)` are denied, and `permissions.disableBypassPermissionsMode` is `"disable"`.

**Permission tiers for unattended runs** ([ADR 0013](adr/0013-permission-tiers-for-unattended-runs.md)). An agent started from Orca's mobile app must not wait on a prompt (goal 9), while irreversible actions stay blocked. `settings.common.json` holds the tiers, so they reach `settings.json` on every host and profile:

| Tier | Holds | Where |
|---|---|---|
| `permissions.deny` | The credential reads above | `settings.json`, and the macOS drop-in |
| `autoMode.hard_deny` | `$defaults`, a force-push to main, destructive database commands, `op` writes whose output is not discarded, a merge with `--admin` or by any route around the rulesets | `settings.json` |
| `autoMode.soft_deny` | `$defaults`, a force-push to a pull request branch, posting anywhere but GitHub pull requests and issues and Linear, `rm -rf` outside the scratchpad and the temporary directories, changing `gh`'s default repository, editing git remotes | `settings.json` |
| `autoMode.allow` | Its defaults only | `settings.json` |
| `permissions.allow` | `gh pr checks` and `gh pr view`, exactly, with no argument | `settings.json` |
| `permissions.ask` | Nothing: a prompt would stall the run | — |

- An allow rule decides before auto mode's classifier runs, so neither `hard_deny` nor `soft_deny` sees a command one matches, and a `*` in it matches any text, spaces included. So the allow list holds only reads with no argument: with a URL or `--repo` a read can name another host, which a review flagged as a way for data to leave in the URL (**Unverified**).
- A merge has no allow rule. A form with a pull request number needs a `*`, which also takes `--admin`, `--repo`, `--body`, `--subject` or `--body-file`. A form without one (`gh pr merge --squash`) merges in whatever repository `gh`'s default and the git remotes point to, which `gh repo set-default` and `git remote set-url` can change, and `gh` refuses `--repo` without a number. The classifier decides each merge. By default it blocks one no human approved, and in an interactive session 3 blocks in a row or 20 in total make auto mode pause and prompt, so a request that names the merge clears it, and `hard_deny` still blocks `--admin`. An exception for the session's own pull requests was dropped (ADR 0013): the classifier cannot see whether checks passed, and the exception would apply in repositories with no ruleset. Changing the default repository or a remote is `soft_deny`.
- A push has no allow rule. A rule that names a non-main branch needs a `*`, which also takes a second refspec or a force flag after a tab or an expansion as well as after a space, and a rule without one (`git push -u origin HEAD`) pushes `main` from a `main` checkout. The classifier allows a push to any branch of the working repository by default and still applies `hard_deny` and `soft_deny` to it. A repository's ruleset on its default branch holds whatever the spelling; this repository's blocks force-pushes and deletion and requires signed commits and status checks there (`verification.md`).
- `tests/*.sh` and `rm` under the scratchpad and `$TMPDIR` have no allow rule either. The first would run a script the agent wrote itself, and the second takes any further target after its prefix (`rm -rf <scratch>/x ~/repos`). The classifier decides both, and lets a named scratch path be deleted by default.
- `tests/agents.sh` decides a fixed list of commands under the generated rules with a model of the documented matcher, and checks the model against the docs' own table of wildcard examples. Whether it agrees with Claude Code's matcher on every command is **Unverified**.

**Environment facts for agents.** `~/.claude/CLAUDE.md` (the same file as `~/.codex/AGENTS.md`) states:

- where repositories live (`~/repos/github.com/<owner>/<repo>`, through ghq);
- global tools are added to `nix/packages.nix`, never with brew, and with a language package manager (`npm -g`, `uv tool install`, `cargo install`) only when nixpkgs lacks them, with an `outsideNix` entry (ADR 0014);
- project tools come from the project layer's default;
- GitHub tokens come from ghtkn: never run `gh auth login` or export a token.

**Guardrails.** See [ADR 0007](adr/0007-agent-guardrails.md). Protection is split into three layers: the sandbox enforces Bash reads, writes, and network (enabled only after measurement, below); `permissions.deny` covers Claude's file tools and common Bash forms (for example `Read(~/.aws/**)`); hooks are tripwires for judgements the other two cannot express. Claude Code's docs state that hooks and Bash patterns are not a security boundary, and that a PreToolUse hook that cannot start, exits with a code other than 0 or 2, times out, or prints invalid output lets the call proceed unless it sets `onFailure: "block"` (Claude Code v2.1.295 or later; no effect on `async` hooks).

This repository manages only hooks whose need spans repositories. A hook that concerns one project lives in that project's `.claude/settings.json`, as one repository already does for its own `UserPromptSubmit` guard; the other repository-level settings checked only enable plugins. Each hook below was kept on evidence from the 70 active `paveg` repositories and from past sessions (counts in [`verification.md`](verification.md)).

Hooks come in three kinds, decided by what a failure of the hook should do:

- **Guard**: protects data or credentials. It fails closed (`onFailure: "block"`, explicit `deny` on malformed input). Its rules are a table of exact `deny` rules and shape `ask` rules, and it never prints `allow`.
- **Checker**: enforces a writing or code-quality rule. It denies on a match with a reason the agent can act on, but fails open: a bug in a style check must not halt an unattended agent loop.
- **Injector**: adds context. It never blocks and fails open.

| Hook | Event (matcher) | Kind | Fate |
|---|---|---|---|
| Destructive-database guard | PreToolUse (Bash) | Guard | Kept, rebuilt with `writeShellApplication`. 14 of the 70 active repositories carry drizzle configs or SQL migrations |
| Credential-read guard (`block-sensitive-read.sh`, under a name AGENTS.md lets a tracked file carry) | PreToolUse (Bash) | Guard | Kept until the sandbox's `denyRead` is enabled and measured on the host, then removed. `Read(...)` deny rules alone miss Bash reads they do not recognize (`grep -r`, a script that opens files itself). It matches a credential name wherever it stands as a path segment, so a Bash read of this repository's own `home/.ssh/config` is denied too |
| Unsigned-commit guard | PreToolUse (Bash) | — | Removed. Replaced by deny rules for `--no-gpg-sign`, `-c commit.gpgsign=false`, and `git config … commit.gpgsign`, plus GitHub's "require signed commits". Revisited with the unattended-signing question |
| Comment-rot check | PreToolUse (Write, Edit, MultiEdit, Bash) | Checker | Kept, rewritten from Python |
| PR-body, browser, and Japanese-writing context | PreToolUse (Bash; `mcp__claude-in-chrome__*`; Write, Edit) | Injector | Kept |
| Unaddressed-request check | Stop (`type: "agent"`) | Checker | Kept as a prompt in `settings.common.json`; there is no script to build |
| Reply-language check | Stop | Checker | Added. When the user's last message is Japanese and the reply is mostly English (code, inline code, and URLs left out), it sends Claude back to rewrite once. A written rule in memory and CLAUDE.md did not stop the drift: the user corrected it more than ten times across two sessions. Replies under 20 words are not judged |

Entries owned by other tools:

| Owner | Entries | Identified by | How the generator keeps them |
|---|---|---|---|
| Orca | 16 hooks (agent status, `PreToolUse` and `PermissionRequest` decisions by Orca) | `agent-hooks/claude-hook` | Writes them itself from `nix/orca-hooks.json` (see Generated `settings.json`) |
| herdr | 1 `SessionStart` hook, kept only if herdr is adopted (see Open questions) | `herdr-agent-state.sh` | Not yet: once herdr is adopted, carried over from the current file, which a concurrent write can lose |

- `onFailure` does not cover a guard that exits 0 with no output: plain stdout is not a failure, so the call proceeds. It proceeds through the normal permission flow; exit 0 with no output is not an approval. A guard must never print `allow`, because `allow` skips the permission prompt. So a guard prints `deny` for an exact rule, `ask` for a shape rule (when a command names something protected and uses an expansion, a comment, or a dot-word that starts with an expansion that no matcher can read; see ADR 0007), and nothing otherwise, and the risk to close is a guard that errors before reaching its `deny`. Shell error handling does not close it in general (measured): `errexit` (on by default in `writeShellApplication`) is suspended inside `if`, `&&`, `||`, and `!`, and inside `$(…)` unless `shopt -s inherit_errexit` is set, which `writeShellApplication` does not do. What the guard design guarantees, and what it does not:
  - Guaranteed: a dependency cannot be missing (pinned, `inheritPath = false`); a guard that aborts prints a fixed `deny` from an `EXIT` trap, so stopping the call does not depend on `onFailure`; and a guard that cannot start at all is blocked by `onFailure: "block"`.
  - Narrowed, not guaranteed: an internal error that the script reads as "no match" lets the call through to the normal permission flow. A matcher that errors inside `if grep …` is the measured case. Guards set `shopt -s inherit_errexit`, and check matcher exit codes explicitly (`grep` returns 1 for no match and 2 for an error; only 1 counts as no match).
  - The remaining gap is why guards are tripwires rather than a boundary, and why the upgrade condition below exists.
- What an `ask` does, from Claude Code's hooks page (code.claude.com/docs/en/hooks; read, not run here): `"ask"` prompts the user to confirm, and the reason is shown in the prompt. In auto mode a PreToolUse hook's `"ask"` normally goes to the permission prompt and the classifier does not decide it. In a `claude -p` run where nobody can answer a prompt, a call that would prompt is denied, and Claude reads the reason in the tool result. Among PreToolUse hooks the precedence is `deny` > `defer` > `ask` > `allow`. The docs do not say whether a matching `permissions.allow` rule suppresses a hook's `ask` (**Unverified**: measure it on a real session before relying on an ask to stop a command that an allow rule also covers).
- Every script hook is built with `writeShellApplication` with `inheritPath = false`: `runtimeInputs` pins `jq`, coreutils, and grep, so nothing is resolved from the caller's PATH, and shellcheck runs at build time. The default, `inheritPath = true`, appends the caller's PATH. The generated `settings.json` refers to hooks by store path.
- A running guard is a store path, so editing its source in this repository changes nothing until the next switch, which a human runs. An `Edit` deny rule on `~/.claude/settings.json` stops the agent from repointing hooks by accident. Neither stops a hostile agent. On `personal-mac`, and on `work-mac` when no higher managed source applies, the guards' managed copy is root-owned, so removing the copy in `settings.json` does not disable them. On `wsl` there is no managed copy (see Generated `settings.json`).
- Sandbox: Claude Code's docs say that on macOS, with `allowUnixSockets` unset, the sandbox blocks every Unix socket. The 1Password SSH agent socket, the ghtkn agent, and the Nix daemon socket must be listed there. On Linux and WSL2 that list is ignored and only the all-or-nothing `allowAllUnixSockets` applies. Set `failIfUnavailable: true`, because by default Claude Code runs commands unsandboxed when the sandbox cannot start. Before enabling it with `allowUnsandboxedCommands: false`, measure on each host that those sockets and `op` / `ksm` still work.
- Upgrade condition: if a concrete bypass of the database guard needs closing (for example through `bash -c`), rebuild that guard as a Go binary that parses commands into a syntax tree.

**Safe updates.** Hooks, skills, and scripts ship with tests that run in CI. Removing a rule from a guard's table, or changing its tier, fails the guard's test: every rule is proved on its own (its fixtures get its decision from the built guard, and the decision changes when only that rule is removed), and has near-miss commands it must not reach. A sample of other breaks of the tables, the normalizer and the build (`tests/mutate-hooks.sh`) fails it too; what the guards leave open is listed in ADR 0007. CI also generates `settings.json` and checks that it is valid JSON and contains the required hooks and Orca's entries, and that the macOS drop-in contains the guards, using `profiles/work.example/` for the work side (`tests/agents.sh`, with mutants in `tests/mutate-agents.sh`).

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
| SSH agent | `IdentityAgent` pointing at 1Password's socket for `Host *` (`nix/ssh_config`, as 1Password's get-started page gives it) | Forward to Windows `ssh.exe` (`core.sshCommand ssh.exe`, in `wsl.gitconfig`) |
| Commit signing | `gpg.ssh.program` = `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` (`darwin.gitconfig`) | `gpg.ssh.program` = `op-ssh-sign-wsl.exe` (`wsl.gitconfig`), by name; 1Password's WSL page puts it at `/mnt/c/Users/<Username>/AppData/Local/Microsoft/WindowsApps/op-ssh-sign-wsl.exe` from 1Password 8.11.18 |
| `op` CLI | Desktop app integration (Touch ID) | Windows `op.exe`; the Linux-side `op` cannot use the desktop integration |

The ssh config:

- `nix/home.nix` installs `nix/ssh_config` as `~/.ssh/config` on macOS only, as a copy in the store rather than a link into the checkout like the other files. An edit in the repository then reaches the live file only through a switch, which a person runs, rather than at once through an out-of-store link. The source is not at `home/.ssh/config` because no agent on this Mac can write that path (see Open questions), and not elsewhere under `home/`, whose files land in `$HOME` under their real names (`tests/shell.sh` copies `home/` into a temporary `HOME` and fails on an entry off its allowlist). Whether OpenSSH accepts the store copy's owner and mode after a real switch is **Unverified**.
- It holds the `IdentityAgent` line under `Host *`, and a `Host pve` block for the Proxmox host on the LAN, in place of the previous setup's `Include ~/.ssh/config.local` for that one host: `HostName 192.168.10.5`, `User root`, `IdentityFile` naming the public half of a key that the 1Password agent holds (the private key moves into 1Password), `IdentitiesOnly yes`, `ForwardAgent no`, and `HostKeyAlias pve` with `StrictHostKeyChecking yes`, so the host key is pinned under the alias and another machine at that address fails closed. The owner decided the LAN address may be public. The block comes before `Host *`, because ssh keeps the first value it obtains for each key (measured: a `pve` block after `Host *` that set `IdentityAgent none` lost to `Host *`'s socket).
- Not carried over from the previous setup: its `Include ~/.ssh/config.local` itself, the `SSH_TTY` gate that let a forwarded agent win in SSH sessions, and its `Host *` defaults (`IdentitiesOnly`, `UseKeychain`, keep-alives). Each comes back only when it is missed.
- On `wsl` git runs Windows `ssh.exe` (`wsl.gitconfig`), which reads the Windows-side config, so no Linux-side file is installed.
- Tests (`tests/ssh.sh`, CI on Linux and macOS): `ssh -G github.com` and `ssh -G` for another host, each with `-F nix/ssh_config`, resolve `identityagent` to the 1Password socket under the home directory; `ssh -G pve` resolves each value of the `pve` block and the same socket, and `github.com` keeps its own host name and the local user, with no host key alias. OpenSSH expands `~` from the passwd entry, not `$HOME` (measured), so a temporary `HOME` cannot stand in for the real one; `-F` reads the file under test alone, without `/etc/ssh/ssh_config` or the real `~/.ssh/config`, and nothing connects. `tests/mutate-ssh.sh` drops the line, swaps in the Linux socket, drops the quotes, narrows `Host *` to GitHub, turns the agent off in the `pve` block, widens that block to `github.com`, and breaks each of its values. Moving the block after `Host *` changes nothing `ssh -G` prints while no key is set in both (measured), so that move has no mutant. `tests/packages.sh` checks that the built macOS configuration holds a store copy of the file and the `wsl` one none.

Commit signing is decided in [ADR 0005](adr/0005-commit-signing.md).

Known limits:

- `op-ssh-sign` needs the GUI to unlock; it cannot sign headless.
- On `wsl` the signer is named without a path, because its full path holds the Windows user's name. git looks a program name without a slash up on PATH, so it resolves only if the Windows PATH that WSL appends includes `%LOCALAPPDATA%\Microsoft\WindowsApps` (**Unverified**).
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
| Switch (`sudo`) | 2. Rendering the personal `ghtkn.yaml` through `op inject` is 3, so the switch renders it only when the file is missing or its template changed (a hash of the template is stored beside it), and only when 1Password is signed in; otherwise it skips with a warning. At bootstrap step 5 1Password is not signed in yet, so the first render happens at step 8, at the desk | 2 from Orca's terminal on the host, unless the template changed. Over Tailscale SSH, nix-darwin's App Management check no longer forces 3: no app sits in `/Applications/Nix Apps`, so the check has nothing to touch (see Packages). Whether the rest of a switch over SSH, `brew bundle` writing a new cask into `/Applications` included, runs without a class 3 step is **Unverified**. How the switch detects "signed in" without itself raising a prompt is **Unverified** |

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
- `gh` is an executable wrapper (`nix/gh.sh`), built in `nix/ghtkn.nix` with `writeShellApplication`, so shellcheck runs in the build, and installed by `nix/vaults.nix`. It calls the real binary as `${pkgs.gh}/bin/gh`, and `ghtkn` from PATH. The real `gh` is not in `home.packages`, which would collide with the wrapper's name; the wrapper's package carries `gh`'s licence and links its `_gh`, which `.zshrc`'s compinit loads. `_gh` runs `gh __complete`, which the wrapper hands to the real `gh` with no token, so commands and flags complete while the agent is locked; completions that call the API, such as reviewers for `pr create --reviewer`, run with no token.
  - If `GH_TOKEN` or `GITHUB_TOKEN` holds more than whitespace, it runs the real `gh` directly.
  - So it does for a first argument that `gh` runs with no auth check and no API call: help, the version, shell completion, `config` and `alias` (the list is in `nix/gh.sh`; gh's `IsAuthCheckEnabled` and `DisableAuthCheck` in `pkg/cmdutil/auth_check.go` exempt them, and `config` and `alias` use no HTTP client). `auth` and `extension` still go through ghtkn. Only the first argument is read, so `gh pr --help` still asks ghtkn.
  - Otherwise it runs `ghtkn exec -e GH_TOKEN:<app> -- <real gh>`. `<app>` is read from `${XDG_CONFIG_HOME:-$HOME/.config}/ghtkn/gh-app`, beside the `ghtkn.yaml` ghtkn reads, a one-line file, so no org name appears in this repository. A missing or empty file stops it with exit 1 before ghtkn runs: with no app named, ghtkn would choose one itself, the read app on `work-mac`.
  - It runs ghtkn as a child rather than with `exec`, since ghtkn replaces itself with `gh`. On exit code 111 (no token) it tells the user to run `ghtkn agent unlock --enable-refresh`, or `ghtkn auth <app>` for an app never authenticated, and every exit code passes through unchanged. ghtkn 0.4.3 also exits 111 for an app its config does not define (measured).
  - `tests/ghtkn.sh` runs the built wrapper under `env -i` with a stub `ghtkn` and the real `gh`, whose `gh auth token` prints whichever token reached it; `tests/packages.sh` checks that the profile installs that same build.
- The personal `ghtkn.yaml` is rendered by `nix/ghtkn-render.sh`, which a home-manager activation step runs on personal hosts only as `ghtkn-render <template> ~/.config/ghtkn/ghtkn.yaml <op>`, with `/usr/local/bin/op` on macOS and `op.exe` on `wsl`:
  - The hash is the template's sha256, stored in `ghtkn.yaml.template-sha256` beside the file. With a regular file present and the hash unchanged, it calls no `op` at all and only sets the file back to 0600. A link in the file's place is rendered over, so `chmod` never reaches what it points at.
  - Otherwise it renders only after `op whoami` succeeds. Whether `whoami` answers without raising a prompt is **Unverified**; if it reports "not signed in" until a command in that terminal has authorized, the bootstrap has to authorize one before step 8.
  - The template goes to `op inject` on stdin, because `op.exe` cannot open a Linux path. The output goes through a temporary file in the same directory (0600) and `mv -T`, and the hash is written last the same way, so a link in its place is replaced, not written through. The step runs under `umask 077`, so the directories it makes are its owner's alone. An EXIT trap removes the temporary file, and bash runs that trap when INT, TERM or HUP kills it too (measured); a SIGKILL leaves the file, and nothing sweeps it.
  - A missing `op`, a signed-out `op`, a failed `op inject` (an `op://` item that does not exist yet), a directory or temporary file that cannot be made, and a target that is a directory or a link to one (checked before any `op` call) each warn on stderr and exit 0, keeping the old file and the old hash, so the switch goes on and the next one tries again. A hash that cannot be stored once the file is in place warns too, and the next switch renders the file again.
  - Neither switch hands the step the caller's `PATH` by default. nix-darwin's `activate` runs under `env -i` and sets `PATH` to its own grep, coreutils and Nix directories and `/usr/bin:/bin:/usr/sbin:/sbin` (measured in the built system), so on macOS the step names `/usr/local/bin/op`, where the 1Password CLI module installs it, and no stub on the switch's `PATH` reaches it. Until that module is enabled the file does not exist, and the step skips. The standalone home-manager on `wsl` runs `activate` from the user's shell, but home-manager keeps only its own tools on `PATH` (`home.emptyActivationPath` defaults to true from state version 22.11), so `wsl` sets it to false and `op.exe` is found on the Windows `PATH`. Whether `op` reaches the desktop app from either activation is **Unverified**.
  - The template's reference is `op://Dotfiles/ghtkn/client_id`, which the personal GitHub App's item has to match when it is created (Rollout step 1). The item is in a vault of its own rather than Personal, because a 1Password service account can read only custom vaults (see Unattended setup).
- The ghtkn agent runs from `launchd.user.agents` on macOS, which nix-darwin copies into `~/Library/LaunchAgents/org.nixos.ghtkn-agent.plist`, and as the systemd user service `ghtkn-agent` on WSL2 (**Unverified** on WSL2). Both run the profile's own `ghtkn agent start` and restart it only after a failure (`KeepAlive.SuccessfulExit = false`, `Restart=on-failure`), because `ghtkn agent stop` exits 0. The agent starts locked, and ghtkn reads the passphrase only from a terminal, never from an environment variable or a pipe (`pkg/agent/tty/passphrase.go`), so every agent start, a reboot or a switch that upgrades ghtkn included, needs `ghtkn agent unlock --enable-refresh` typed at a terminal: class 2 from Orca's terminal. On WSL2 the service gets `XDG_RUNTIME_DIR` from systemd, and ghtkn puts its socket there before `XDG_CACHE_HOME`, so a client started without `XDG_RUNTIME_DIR` (`env -i zsh -c`) looks for a socket the agent does not listen on (**Unverified**).
- Never set `GITHUB_TOKEN`, `AQUA_GITHUB_TOKEN`, or `AQUA_KEYRING_ENABLED`: aqua then ignores ghtkn. Never run `gh auth login`. The `GH_TOKEN` pass-through exists only for a caller that already holds a short-lived token (for example CI).

### Packages

- `nix/packages.nix`: `claude-code` ([ADR 0011](adr/0011-claude-code-from-nixpkgs.md)), `git`, `ghq`, `fzf`, `ripgrep`, `fd`, `bat` and `eza` (fzf's previews), `zoxide`, the zsh plugins `zsh-autosuggestions` and `zsh-syntax-highlighting`, `jq`, `neovim`, `just`, `lazygit`, `lefthook`, `gitleaks`, kubectl tooling (`kubectl`, `kubernetes-helm`, `k9s`, `stern`; nixpkgs' `helm` is an unrelated synthesizer), `ghtkn` (in nixpkgs), `mise`, `uv`, `rustup`, `elan` (the version managers of [ADR 0012](adr/0012-language-runtimes-from-version-managers.md)), `atuin`. `nix/vaults.nix` adds `gh`, the wrapper from GitHub authentication, under nixpkgs' name.
- The 1Password CLI is not a nixpkgs package on any host: on macOS it comes from the module below, and on `wsl` the Windows `op.exe` is used, because the Linux `op` inside WSL cannot use the desktop app integration. Every `op` call on `wsl` (step 8's `op inject` included) means `op.exe`.
- Unfree packages are allowed by name only. The plan is `claude-code` and `1password-cli`, the `lib.getName` of the `_1password-cli` attribute (evaluated by the macOS module `programs._1password`); today `flake.nix` admits only `claude-code`, because that module is not enabled yet. `claude-code` is the only unfree package in `nix/packages.nix` (measured), and the predicate lives in `flake.nix`, which is where both the nix-darwin `pkgs` and the standalone home-manager `pkgs` for `wsl` are built.
- Everything a host installs has to be usable on the work machine, and `tests/licenses.sh` checks that by evaluation rather than from memory (zsh-abbr, under CC-BY-NC-SA-4.0, nearly went in). It reads `meta.license` from `home.packages` and, on macOS, from `environment.systemPackages`, `fonts.packages`, and the Homebrew casks and formulae, and prints a table of package, licence, and verdict. It fails:
  - on a licence with `NC` as a whole word of its SPDX id or short name, or with "non-commercial" or "noncommercial" in any case in its full name, wherever it sits in the licence (an alternative of an `OR` included) and even for a package allowed by name. A whole word, because `NCSA` is a free licence; the full name, because it is the only mark of `inria-compcert`, `inria-zelus`, and `geogebra`. A full name that spells "Non Commercial" with a space is not matched;
  - on a licence that is not free or not redistributable, unless the `flake.nix` predicate admits the package by name. The predicate is asked, not copied, so the allowance has one list. `allowUnfree` is not asked, so setting it admits nothing. The predicate waives both, because `claude-code`'s `unfree` licence is also not redistributable (measured);
  - on a Nix package with no `meta.license`, unless `nix/licenses.nix` records one under `generated` for that name. home-manager and nix-darwin build a few such derivations themselves, and both projects are MIT;
  - on an install from outside Nix with no entry under `outsideNix.<host>` in `nix/licenses.nix`. Each `winget install` in this file counts as a `wsl` install when it has arguments, and one with none, as in this sentence, names the command. The package is the value of `--id` or `-q`, or else the argument that is neither an option nor an option's value. A command that does not name exactly one package that way (an option the check does not know, one without its value, or two packages) fails as unparsed. Each Homebrew cask or formula counts as an install for its host. A `cask`, `brew`, or `mas` line in `homebrew.extraConfig` fails the check, because that raw Brewfile text is not read. The Windows-side font has no such command, so its entry is kept by hand and nothing finds it missing. A proprietary install recorded there passes, with "proprietary" in its verdict: it is a deliberate manual install, and the `flake.nix` predicate names nixpkgs packages, not winget ids.
- The licence shapes `tests/licenses.sh` reads are a single licence, a list, the `compound` (`OR`, `AND`), `exception`, and `plus` forms of `lib.licenses`, and a bare string. Where a licence lacks the `free` or `redistributable` field, or is a bare string, the check counts it as neither, and an empty list or compound counts as no licence. A package's dependencies are not checked, and neither are `homebrew.masApps`, `users.users.<name>.packages`, or apps that a module installs outside the lists above: a package given as a source to `programs.zsh.plugins` or `home.file` gets no row, so zsh-abbr installed either way passes (measured). Installs from outside Nix are found by parsing prose and Ruby, which misses spellings the shell or Homebrew still runs (all measured by a review agent, none used in this repository): a PowerShell backtick continuation, the `winget.exe` spelling or the `add` alias of the install subcommand, a capitalised `Winget`, and a `cask` that is not first on its `extraConfig` line. PAV-63 replaces the parsing with a structured list rather than widening the patterns. An NC licence whose id has no `nc` word (`PolyForm-Noncommercial-1.0.0` as a bare string) is not recognised. The check evaluates with `--impure` (for `builtins.getFlake` on an unlocked `path:`), so on a machine with nixpkgs overlays in `~/.config/nixpkgs` the `wsl` package set it reads can differ from the one the pure build installs.
- macOS apps, by P8's order ([ADR 0014](adr/0014-tool-sources.md)). Each app is planned to come from a Homebrew cask through nix-homebrew, with an entry under `outsideNix.<host>` in `nix/licenses.nix`; neither host enables Homebrew yet (measured):
  - 1Password (cask `1password`). The app must exist before any `op` step.
  - Raycast (cask `raycast`) and Ghostty (cask `ghostty`).
  - Karabiner-Elements (cask `karabiner-elements`). nix-darwin's `services.karabiner-elements` is broken with Karabiner 15: the module links `org.pqrs.karabiner.agent.*` LaunchAgent plists that the 15.x sources no longer ship, and nix-darwin issue #1041 ("services.karabiner-elements is broken after Karabiner-Elements v15.0") is open, with an activation failure on exactly that. nixpkgs' `karabiner-elements` ships the driver as a separate `driver` output, which the module copied into `/Applications`; installing the package alone would not put the driver there.
  - Orca from its own tap (`homebrew.taps = [ { name = "stablyai/orca"; trusted = true; } ]`, cask `stablyai/orca/orca`; nix-darwin's tap option notes that Homebrew 6.0.0 and later refuse formulae and casks from untrusted non-official taps, aborting activation, while its cask option says such casks are silently skipped and that a fully qualified cask such as `stablyai/orca/orca` is trusted by default; trusting the tap is harmless either way; as Orca's install docs give; nixpkgs' `orca` is the GNOME screen reader, and Homebrew's core `orca` cask is an unrelated, disabled app).
  - The cost of casks: the four from `homebrew/cask` set `auto_updates`, so those apps update themselves. Their versions are in no lock, can differ between hosts, and change with no diff here. A switch installs a missing cask and does not upgrade an installed one (`homebrew.onActivation.upgrade` keeps its default, `false`).
  - No app comes from nixpkgs, so nix-darwin's `/Applications/Nix Apps` holds no bundle. Its `ensureAppManagement` check (`modules/system/applications.nix`) still runs on every switch, but with no bundle there it touches nothing, resets nothing, and does not fail over SSH. An app that has to come from nixpkgs, for want of a cask, brings the check back. Over SSH the switch then fails unless programs run over SSH have Full Disk Access, which this repository does not grant, because that gives every SSH session access to the whole disk. In a GUI session the check resets the App Management decision once, and `tccutil reset SystemPolicyAppBundles` names no app, so that reset clears the decision for every app.
- On macOS, Nix still installs what is not a GUI app: the 1Password CLI (`programs._1password`, which installs `/usr/local/bin/op`: the module notes that the app integration works only with the CLI at that path), Tailscale (ADR 0010), and the font (`udev-gothic-nf` through `fonts.packages`).
- Karabiner-Elements and Raycast are desk tools the owner asked for: neither reaches a process without an interactive shell, so they are a stated exception to P6.
- Karabiner-Elements needs four approvals after install, per its docs: background services, Accessibility, Input Monitoring (normally granted with Accessibility), and its driver extension. They are made once, at the desk. On `work-mac`, whether the company's device management allows the driver extension is **Unverified**.
- Raycast keeps its settings in its own database, not in a file (`~/Library/Application Support/com.raycast.macos/`). The free plan has no Cloud Sync, which needs Pro. So:
  - Script Commands are plain scripts in `home/.config/raycast/scripts/`, which is added once in Raycast's settings as a script directory.
  - Settings, aliases, hotkeys, and extensions are exported with **Export Settings & Data** to an encrypted `.rayconfig` file, stored as a document in 1Password with its passphrase, and imported by hand on a new machine. It never enters this repository: the repository is public, and snippet and quicklink exports are not encrypted.
- Each `hosts/<host>.nix` has `packages = pkgs: [ … ]`, which `nix/packages.nix` appends to the list above for that host alone. Today only `work-mac` adds one: `peco` (0.6.0, MIT in the locked nixpkgs, measured).
- `hosts/work-mac.nix`: Keeper Secrets Manager CLI, aqua, internal tools. The KSM CLI is not in nixpkgs, and Keychain storage needs its pip `keyring` extra; without it the config falls back to a plain `keeper.ini`. Packaging it (a local derivation or another installer) is **Unverified**.
- No language runtimes: the version managers above install them ([ADR 0012](adr/0012-language-runtimes-from-version-managers.md)).
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
  The first design, which kept the guards only in `settings.json` and carried Orca's entries over from the file the generator read, broke both (TLC counterexamples). So did the two fixes this section first proposed (TLC, prototype variants): with the generator re-reading just before writing, Orca's stale write still drops the guards; with the switch restarting Orca, Claude Code's stale write still drops them, and whether a restart ends the agent sessions running in Orca is **Unverified**. The two choices of Generated `settings.json` (guards also in managed settings, Orca's entries written by the generator) are what pass. `check.sh` keeps two mutants: `settings.json` written while the drop-in is missing (the first design's guards), and Orca's entries carried over from the read. The guard property follows from the drop-in, not from the interleavings: it assumes nothing else writes the drop-in and Claude Code reads it (not true when a higher managed source exists, above). The model also assumes the switch writes the drop-in before `settings.json`; the mutant shows the property fails without the drop-in. `tests/agents.sh` checks that order in the generator: on each Mac the system activation runs the drop-in write before home-manager and never writes `settings.json` itself, and the generator refuses to write `settings.json` while the drop-in it is given is missing or lacks the guards.
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
2. Install Determinate Nix if `nix` is missing, then load its profile into the running script. On WSL2 without systemd, stop and say how to enable it. On a Mac with upstream Nix, stop and point to Determinate's macOS package (below). On `wsl` with a Nix whose `nix-command` is off, as upstream Nix's default is, stop and say to turn on `nix-command` and `flakes` or install Determinate Nix. The script tells by whether `nix eval --expr 1` succeeds (measured on upstream Nix 2.33.0: it exits 0 with `nix-command` on, and with it off fails with `experimental Nix feature 'nix-command' is disabled`; it still exits 0 with the daemon unreachable). Nix's own error is shown above the instruction, as the script does not tell that failure from another. A Nix with `nix-command` on and `flakes` off is not told apart and fails at step 4 with Nix's own error, which names the feature to turn on. The list in `nix config show experimental-features` could tell it, but Determinate Nix calls flakes stable, with no experimental features to enable (its docs), and does not say whether it still lists them, so a check on that list could stop the intended Nix.
3. Record `<host>` in `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host`. The XDG variables are not set yet (`~/.zshenv` arrives with the first switch), so the script uses the spec default. `just switch` reads this file, so later switches never take a host name again.
4. Clone over HTTPS with git and ghq from nixpkgs (no SSH key yet; no git is assumed on the host): `GHQ_ROOT=~/repos nix shell nixpkgs#git nixpkgs#ghq -c ghq get https://github.com/paveg/dotfiles`, then work from `~/repos/github.com/paveg/dotfiles`. On an existing checkout `ghq get` prints `exists` and exits 0 without running git (measured).
5. First switch: installs packages and apps, including Homebrew (nix-homebrew) and the casks on macOS, 1Password's among them (on `wsl` 1Password is a Windows-side prerequisite), and the ksm CLI on work-mac. macOS: `sudo nix run nix-darwin -- switch --flake .#<host>`; WSL2: `nix run home-manager -- switch --flake .#<user>@wsl`. The script then prepends the profile's bin directories (`/etc/profiles/per-user/$USER/bin` on macOS, `~/.nix-profile/bin` on WSL2) to its own PATH, so the tools the switch installed are found in later steps.
6. Human: sign in to the 1Password app; enable the SSH agent and CLI integration.
7. work-mac only, skipped when `~/.config/dots-work/` already exists, so a rerun never overwrites unpushed work-profile edits:
   - If Keeper Secrets Manager is available: human, `ksm profile init <one-time token>`, skipped when a KSM profile already exists; the script then runs `scripts/work-sync.sh pull`.
   - Otherwise: human, place the work profile in `~/.config/dots-work/` by hand (the fallback in ADR 0002), then press Enter.
8. Second switch: links the work profile and renders the personal `ghtkn.yaml`. Then `mise install` installs the global runtime defaults, which `mise ls` shows as `(missing)` until it runs (ADR 0012). It has no action of its own in `spec/bootstrap.tla`.
9. Human: `ghtkn agent unlock --enable-refresh` sets the passphrase on the first run; then `ghtkn auth` once per app, which runs the device flow in the browser. The order follows ghtkn's docs: no token can be obtained until the agent is unlocked.
10. Install the repository's git hooks (`lefthook install`) when the checkout has a `lefthook.yml`. In a repository without one, `lefthook install` writes an example `lefthook.yml` and a `prepare-commit-msg` hook (measured, lefthook 2.2.2), and a later pull that adds the real file would stop on the untracked copy.
    On macOS the script then prints a checklist of one-time GUI steps: Karabiner's approvals, adding Raycast's script directory, and importing the `.rayconfig` from 1Password (skipped on a first machine that has no export yet). On `wsl` the checklist names the Windows-side steps instead: the `winget install` commands for Windows Terminal, Orca, and Raycast, and the same `.rayconfig` import. 1Password and its CLI are not on the checklist: they are prerequisites, and step 6's check (a stub `ssh-add.exe` in CI, the real one otherwise) fails until they are installed. They are a checklist rather than human steps that wait for Enter, because nothing in the bootstrap depends on them, so they need no check and the run can finish without them.

Work and personal are kept apart by the host, never by guessing:

- The host is a required argument. The script does not infer it from the hostname, the hardware, or a network.
- Only `work-mac` runs step 7, and only `work-mac`'s configuration links `~/.config/dots-work/`. A personal host never calls `ksm` and never creates that directory.
- On `work-mac` the script does not run the second switch until `~/.config/dots-work/` exists, so the machine cannot finish half personal.
- Changing a machine's host, for example after a first run named the wrong one, is done by hand and the script never does it: push any work-profile edits, then delete the recorded host, `~/.config/dots-work/`, and the KSM profile together. Deleting only the recorded host leaves the work profile on what is now a personal machine (TLC counterexample on `spec/bootstrap.tla`).

Notes:

- Every step must be safe to rerun, so a stopped run is resumed by running the same command again. Step 7 achieves this by skipping what already exists; `ksm profile init` itself consumes a one-time token and is never repeated. Step 3 writes the host beside its file and renames it into place, and reads an empty file as no host, so a run stopped while recording it leaves nothing that refuses the next. `tests/bootstrap.sh` checks it with every command stubbed: no run changes an existing checkout or the hand-placed work profile, and a second complete run changes nothing below `$HOME`.
- `DOTFILES_REF` is planned and not in the script yet: it lands with the bootstrap runs on real machines in Verification, its only user. When set, it is to make step 4 run `git fetch origin <ref>` and `git checkout --detach FETCH_HEAD` in the checkout after `ghq get`, so CI runs the bootstrap against the commit under test. `ghq get` alone cannot do this: it takes only a branch name, and on an existing checkout it runs no git command (measured). Without `DOTFILES_REF`, step 4 never moves an existing checkout.
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
- Generate and check `settings.json` (work side from `profiles/work.example/`): `.github/workflows/agents.yml` runs `tests/agents.sh` on Linux and macOS and `tests/mutate-agents.sh` on macOS. The test builds the generator and the hooks, runs the generator in temporary home directories (personal, work, work without its profile, a profile that repeats a common rule, a file Orca has already merged into, a linked file, a local file on each side), checks each output and the drop-in, refuses an IPv4 literal in any tracked settings JSON, reads each host's activation from the evaluated configuration, and evaluates the `~/.claude` and `~/.codex` links each host gets, on a copy of the repository with a placeholder for each linked entry and skill.
- Tests for hooks, skills, and scripts.
- `.github/workflows/repo-checks.yml` runs the repository-wide checks on every pull request and every push to `main`, with no path filter, one job per check, so each job name (`gitleaks`, `deny-paths`, `diff-check`, `actionlint`, `zizmor`) is a status check that branch protection can require. gitleaks, actionlint, and zizmor come from the nixpkgs in `flake.lock` (`nix shell --inputs-from . nixpkgs#<tool>`), so a local run uses the same versions.
- The other workflows (`shell`, `hooks`, `agents`, `nix`, `spec`, `bootstrap`) have no path filter either, so their aggregate jobs `shell-passed`, `hooks-passed`, `agents-passed`, `nix-passed`, `spec-passed`, and `bootstrap-passed` report on every pull request and can be required. A required check whose workflow a path filter skipped would never report and would block the merge. Each workflow's `changes` job runs `tests/workflow-changed.sh <workflow>`, which reuses the diff of `tests/lib/mutate.sh`, and prints `changed=false` only when the pull request changes none of that workflow's inputs: its former `paths` entries, `.github/workflows/`, `flake.nix`, `flake.lock`, and the script with its helper. An unset base or a diff git cannot compute means changed. The other jobs then skip every step and still succeed. A step runs unless that output is `false`, so a push to `main`, where the decision step does not run, runs every step. A job whose steps are all skipped runs on `ubuntu-latest` even where it would use a macOS runner, so a pull request that changes no input takes no macOS runner. How long such a pull request takes, and that the skipped and rerouted jobs behave so on GitHub, is **Unverified** until one has run. An aggregate still fails when a job it needs was skipped, so require the aggregates, not the jobs below them. `tests/workflow-selection.sh` checks the decision through git in a throwaway repository, one changed path per former `paths` entry, and `tests/mutate-selection.sh` breaks it.
- gitleaks over the whole history of the checked-out commit (`tests/gitleaks.sh`: `gitleaks git --redact --log-opts='--diff-merges=first-parent HEAD'`, with `fetch-depth: 0`). Without `--log-opts`, gitleaks scans every ref (measured), so a leak on an unrelated branch would fail every pull request. `git log -p` prints no patch for a merge, and on a pull request HEAD is itself a merge, so with `--log-opts=HEAD` alone a file that only a merge adds, or a secret typed into a conflict resolution, passes (measured); `--diff-merges=first-parent` shows each merge against its first parent. `tests/mutate-gitleaks.sh` shows the scan refuses a secret added by an ordinary commit, by a merge, by a conflict resolution, and by a branch commit whose file a later commit removes before the merge, and passes one that only an unmerged branch holds. The last case is why the scan reads every commit, not only HEAD's. Because a merge reports a branch's leak again under the merge's own SHA, and a pull request's merge SHA changes on every run, a `.gitleaksignore` entry for a known false positive must be the global form (`<file>:<rule>:<line>`), not one pinned to a commit (measured by a review agent). The binary is used rather than `gitleaks/gitleaks-action`, which needs no license for a personal account but takes a `GITHUB_TOKEN` to comment on pull requests.
- No tracked path matches a `Read(...)` deny pattern in the common settings, so every file stays readable to the agents that maintain it. `tests/deny-paths.sh` reads the patterns from `home/.claude/settings.common.json` rather than a copied list, and lets git match them as gitignore patterns from the repository root, with case folded on every OS, and a one-segment directory rule such as `Read(secrets/**)` matched at any depth, as Claude Code reads it in a deny rule. A home rule (`~/...`) reaches the checkout only through `~/repos`, so one whose first segment is a literal name other than `repos` in any case is skipped; a rule the check cannot place against the checkout (`//`, `/`, `./`, `!`, `#`, a home rule starting with `repos` in any case or with a glob) fails it. `tests/mutate-deny-paths.sh` shows it refuses a tracked path for each rule and passes near misses. With case folded, `Read(**/*password*)` also matches the planned `home/.config/1Password/ssh/agent.toml` (measured), so that file cannot be added under that name until the rule or the path changes.
- actionlint and zizmor (`--offline`, so no token is needed and the result does not depend on the GitHub API) over every workflow and `dependabot.yml`.
- Shell tests, without a switch, on any runner and locally: a temporary `HOME` holds only this repository's `home/` files, and `env -i` starts `zsh -c`, `zsh -lc`, and an interactive zsh fed commands on stdin (`zsh -ic` runs no history or `preexec` hooks, measured). They check:
  - the four XDG variables, `ZDOTDIR`, and `ATUIN_HOME` take the expected defaults, and an `XDG_CONFIG_HOME` set by the caller is kept;
  - with stock `/etc` files, `.zprofile` puts Nix's directories ahead of `/usr/bin` in a login shell;
  - the interactive shell writes no history file and creates `$XDG_CACHE_HOME/zsh`;
  - after the shells exit, every entry in `$HOME` is on an allowlist, which catches a stray history, completion dump, rc file, or `~/.atuin`;
  - each variable repeated for launchd or `environment.d` equals its value in `$ZDOTDIR/.zshenv`.
- Git tests, without a switch, in the shell workflow on Linux and macOS: `tests/git.sh` and its mutants `tests/mutate-git.sh` (see Git), and `tests/ssh.sh` with `tests/mutate-ssh.sh` (see 1Password agent).
- Package tests, on the built configuration and still without a switch: each build job evaluates its host's `pkgs` set and home-manager configuration, builds `home.path` and `home-files`, and checks that `home.packages` names exactly the attributes above, plus the host's own and the entries home-manager adds itself, that `allowUnfree` is false and the predicate admits `claude-code` and refuses every other name it is asked about (a prefix of `claude-code` and that name with a suffix among them), that every global tool is in the profile, that `env -i PATH=<profile>/bin:/usr/bin:/bin zsh -c 'command -v <tool>'` answers with the profile's copy rather than `/usr/bin`, that the profile PATH names serves that same profile (`/etc/profiles/per-user/<user>/bin` in the built system on macOS, the generation's `home-path` on `wsl`), that `~/.config/zsh`, `~/.config/mise` and `~/.config/git` are real directories and that `~/.zshenv` and their entries resolve to `<home>/repos/github.com/paveg/dotfiles/home/<path>` in full (`~/.config/git/platform.gitconfig` to the file for the host's OS), that `~/.ssh/config` is a store copy of `nix/ssh_config` on macOS and absent on `wsl`, and that the global mise config refuses an `asdf:` tool with `mise settings get disable_backends` reading exactly `["asdf"]`, and on macOS that the built system's `activate` sets each launchd variable in the user's domain. Every check has a mutant except the ones that guard the test harness itself and the `wsl` generation's own link to the profile. The per-user profile and launchd mutants run in the macOS jobs, where that system is built, the host-independent ones on the Linux runner, and the per-host ones in every job.
- Licence check, by evaluation alone: each host job runs `tests/licenses.sh` for its host before it builds, and `tests/mutate-licenses.sh`, which breaks one condition at a time (zsh-abbr installed, with and without an allowance by name; an unfree package; a free but non-redistributable licence; the allowance emptied; an NC alternative in an `OR`; an unfree part of an `AND`; a licence list, a bare string, and a licence without its fields; a missing `meta.license`, an empty list, and an empty `AND`; a missing entry for a generated derivation, a `winget install`, or a Homebrew cask or formula; `allowUnfree` set with an unfree package; NC only in a full name, as a bare string, only in a short name, under `WITH` and `PLUS`, and on the font kept by hand; an unfree base under `WITH`; a `winget install` with `-e` or `--exact` before `--id`, with `--id=`, with two spaces after `winget` or after `install`, and with `-s msstore` before the id, and one with an unknown option or two packages; a cask given through `homebrew.extraConfig`), and also requires a pass for `bat`'s compound `OR` licence and for `NCSA`. The winget and by-hand mutants run in the `wsl` job and the system, font, and Homebrew ones in the macOS jobs.
- `.github/workflows/bootstrap.yml` runs `tests/bootstrap.sh` on Linux and macOS, and `tests/mutate-bootstrap.sh` on Linux. The test feeds `scripts/bootstrap.sh` on stdin, as `curl | bash` does, under `env -i` in throwaway homes, with a stub for every command it calls; the `uname` stub picks the OS, so every host runs on either runner. `DOTFILES_TEST_ROOT` stands for `/` in the Nix profile and systemd paths the script probes, so the runner's own Nix and systemd decide nothing, and a trace sourced through `BASH_ENV` logs each `Step*` function the script enters, in order with the stubs' calls. It checks that a missing or mismatched host, or a dangling host link, exits 2 having run only the host check and changed nothing; that without nix a Mac runs Determinate's installer and goes on with the nix it installed, and `wsl` without systemd waits; that upstream Nix stops each Mac, and stops `wsl` only with `nix-command` off; that a command failing with 2 or 75 fails the run with 1; that an empty host file records no host and a run killed while recording one leaves none; that a run with one human step undone exits 75 at that step having run the steps before it and no more, recorded the host, and added only allowed entries, and finishes once the step is done, and that on a terminal the step asks again until its check passes; that a complete run keeps an existing checkout and the hand-placed work profile and a second changes nothing below `$HOME`, link targets included; that `personal-mac` and `wsl` never call `ksm` or create `~/.config/dots-work/`; that the script adds nothing below `$HOME` but the recorded host, the checkout, and what the stub nix writes there; that a checkout without `lefthook.yml` gets no hooks and no file; that `mise install` follows the last switch, with the switched profile's directory on `PATH` behind the stubs; that the host file follows `XDG_CONFIG_HOME`; and that the step functions a complete run enters are the model's step actions in the model's order. The login-shell `git` check and `$HOME` after a real switch need the runs below.
- Bootstrap tests on real machines, planned and not in any workflow yet, run `scripts/bootstrap.sh` from the start with `DOTFILES_REF` set to the commit under test: `wsl` on a Linux runner as a newly created user with an empty home, and `personal-mac` and `work-mac` on a macOS runner, whose preinstalled Homebrew exercises `autoMigrate`. Whether a hosted macOS runner can run a nix-darwin switch is **Unverified**.
  - Human steps are stubbed by making each step's check pass, so the script's own logic runs unchanged:
    - 1Password on macOS: a real Unix socket listening at the agent socket path, so the check can stay `test -S`. On WSL2, where SSH goes through `ssh.exe`, a stub `ssh-add.exe` that lists one key.
    - 1Password sign-in for the `ghtkn.yaml` render in step 8: a stub whose `inject` writes the template with placeholder client IDs, named `op.exe` on WSL2. On macOS the render calls `/usr/local/bin/op` by path, which a stub in `DOTFILES_TEST_STUB_DIR` does not replace (see GitHub authentication); how the macOS bootstrap test stubs it is open.
    - Keeper: `profiles/work.example/` placed in `~/.config/dots-work/` (the hand-placed path of step 7, so `ksm` is never called).
    - ghtkn: a stub `ghtkn` that exits 0.
  - Stubs live in `DOTFILES_TEST_STUB_DIR`, which only CI sets and which the script announces when set. The script puts it at the front of PATH after every PATH change, including after step 5, so a stub always wins over the real tool.
  - When a check fails and no terminal is attached, the script exits with a distinct status, 75 ("waiting for a person"), instead of waiting for Enter, so CI fails rather than hangs.
  - They check:
    - a missing or mismatched host exits non-zero and changes nothing;
    - a run with one stub removed exits with the "waiting for a person" status, and resumes and finishes once the stub is back;
    - a second complete run changes nothing;
    - a login shell after the real switch resolves `git` from Nix;
    - `$HOME` gains no entry outside the allowlist: on Linux by listing the new user's home, on macOS by diffing the runner's home before and after.
- `git diff --check origin/main...HEAD`, the same check lefthook runs before a commit (the job checks out with `fetch-depth: 0`, since a shallow checkout has no `origin/main` merge base and the command would fail), so a commit made without lefthook installed still cannot merge leftover conflict markers. The job takes the base branch from the pull request; on a push to `main` it checks the pushed range (`git diff --check <before> HEAD`), or the whole tree when the previous commit is not in the clone: a push with no previous commit, or one after a force-push, where `git diff` would exit 128 on the missing commit (measured).
- Every test is shown to fail on a deliberately broken subject (for example, the `ZDOTDIR` line removed, or the host check skipped), and that mutation run is part of CI. A mutant that needs a platform behaviour (the `.zprofile` one needs an `/etc` that reorders the login PATH) runs where that behaviour exists and is reported as skipped elsewhere. The mutants must come from someone other than the test's author too: the first shell tests passed 39 of 53 mutants written by a reviewer (recorded in #23).
- Not covered by CI: real 1Password, Keeper, and ghtkn authentication, Orca, `scripts/unattended-setup.sh` and Tailscale, the corporate proxy, and a real user's WSL2 setup (the Windows-side apps and the Windows PATH of that machine); the `windows-2025` job below covers WSL2 itself only as far as it states. The monthly run covers the bootstrap; `scripts/unattended-setup.sh` and Tailscale are covered only by the manual acceptance criterion for the unattended host.
- Templates: each flake template is instantiated and checked (see Project layer).
- `.github/workflows/spec.yml` runs `spec/check.sh`: TLC on each model, and on one mutant per property that must fail on that property (see Formal models).
- Windows runner: the `wsl` bootstrap test also runs on `windows-2025`, whose image lists "Windows Subsystem for Linux (Default, WSLv2)", in an Ubuntu distro installed by `Vampire/setup-wsl` (the image has no distro; the action defaults to WSL 2 and its `wsl-conf` input writes `/etc/wsl.conf`, which is used to set `[boot] systemd=true`). If systemd is still not running, step 2 stops as the Bootstrap section says, and the job fails: that is a defect in the job to fix, not an expected stop. A separate step runs `ssh.exe -V` from the distro to check interop, because the bootstrap never exercises it in CI: step 4 clones over HTTPS, and step 6's check uses a stub `ssh-add.exe`. Whether the `wsl-conf` route brings up systemd on a hosted runner, and whether the image ships an `ssh.exe`, are **Unverified**. The image's software list has no winget, so the Windows-side installs are not tested in CI.
- Monthly: run the bootstrap on a fresh macOS user account or Linux VM.
- Weekly: `DeterminateSystems/update-flake-lock` opens a pull request that updates `flake.lock`. A pull request opened with the default `GITHUB_TOKEN` does not trigger CI (the action's README), while one opened with a GitHub App token triggers `push` and `pull_request` workflows (peter-evans/create-pull-request, which the action uses), so the workflow mints a token with `actions/create-github-app-token` from a GitHub App made for this job alone: installed only on this repository, with Contents and Pull requests write and nothing else beyond the Metadata read that every App has. Its App ID and private key are repository secrets. The private key is long-lived, but it can mint tokens only for this repository and only with those two permissions.
- Dependabot updates GitHub Actions versions (`github-actions` ecosystem only), weekly, with a seven-day cooldown (zizmor's `dependabot-cooldown` audit flags a shorter one).

## Acceptance criteria

- [ ] A fresh macOS / WSL2 machine is ready after one bootstrap command (first-time 1Password, Keeper, and ghtkn authentication, Karabiner's approvals, Raycast's script directory, the Windows-side Windows Terminal, Orca, 1Password, 1Password CLI, and Raycast installs for `wsl`, and the Raycast import excepted; `personal-mac`'s unattended setup is a separate, manual step)
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
- [ ] Breaking one condition of a guard makes its test fail, and so does removing one rule from its table
- [ ] `.zshrc` defines at most 5 aliases

## Open questions

- Commits made while the host is unattended start unsigned and are re-signed at the desk before a pull request (ADR 0005's fallback). If waiting for the desk becomes the bottleneck, the next step is a dedicated signing-only key in the Secure Enclave (Secretive), registered on GitHub as a signing key only (ADR 0005). Whether it signs while the screen is locked is **Unverified** and is measured before adopting it. Commits through GitHub's API are not pursued. GraphQL `createCommitOnBranch` is signed by GitHub "if supported" even under a user token, but it replaces `git commit`: the agent sends file contents to the API instead of committing locally, so local git hooks do not run (ADR 0005).
- Secrets that agents need while the host is unattended: a 1Password service account (`OP_SERVICE_ACCOUNT_TOKEN`) reads only custom vaults, never Personal, Private, or Employee, and its token then lives on the host.
- Whether to enable the Bash sandbox by default, after measuring the sockets and network calls it must allow.
- Whether to auto-start a terminal multiplexer (tmux / herdr) in interactive shells at all.
- Whether Keeper Secrets Manager is available at work (ask IT).
- 1Password auto-lock timeout.
- How to run the ghtkn agent on WSL2, including which socket path the service and its clients agree on (see GitHub authentication).
- Where the ghtkn agent's passphrase is kept. ADR 0004 does not say, and ghtkn reads it only from a terminal, so whatever holds it is for the person who types it.
- Where Orca creates its worktrees, and whether that location needs its own ignore entry.
- Where the ssh config's source lives. The global `~/.claude/settings.json` of the previous setup denies `Edit(**/.ssh/*)`, so no agent on this Mac can create `home/.ssh/config` (measured), and `tests/deny-paths.sh`, which reads only `Read(...)` rules, does not notice. A source path outside `.ssh` behind an out-of-store link would let agents edit the live `~/.ssh/config`, the edit that rule denies at `.ssh/*`. The source is therefore `nix/ssh_config`, copied into the store (see 1Password agent), until the owner chooses between that, `home/.ssh/config` written by a person, and a narrower rule.
- Whether `ORCA_TELEMETRY_DISABLED` and `HOMEBREW_NO_ANALYTICS` also go into `$ZDOTDIR/.zshenv`, so that the equality check for variables repeated in launchd applies to them.

## Rollout

1. Create this repository with the minimum: flake, `.zshenv`, `.zshrc`, git, ssh, `~/.claude`. Create the personal GitHub App for ghtkn. Create the lock-update GitHub App described in CI and store its secrets.
2. Switch `personal-mac`. If it is wiped and bootstrapped fresh instead, first run `scripts/pre-wipe-inventory.sh`, which lists without changing anything what the wipe would lose, and settle every item it marks as needing action; `work-mac` uses it the same way before step 5. Remove the Tailscale GUI app first (it is installed today), so that the only `tailscaled` is the open-source one nix-darwin runs (ADR 0010). It runs upstream Nix with devbox global on top, so first list what devbox global provides (today it supplies `gh`, `ghq`, `fzf`, `rg`, gitleaks, kubectl, helm, aqua, and just, measured) and confirm each one has a home in the Packages section (aqua goes to `work-mac` only, `gh` becomes the wrapper), judged by P6, then switch to Determinate Nix and run the first switch. devbox global is gone from this point. Remove the native Claude Code install (`~/.local/bin/claude`, `~/.local/share/claude`) once the Nix one works, so only one `claude` exists (ADR 0011).
3. Run it for one to two weeks; pull in from the old repository only what is missed, judged by P6.
4. Roll out to WSL2 (enable systemd first).
5. Roll out to `work-mac`: set up KSM, pull the work profile, verify CA handling.
6. Archive the old repository. Decide first what to do about the company settings in its history.
