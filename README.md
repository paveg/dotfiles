# dotfiles

Nix-based dotfiles for agent-first development on macOS and WSL2. One command turns a fresh machine into a configured host, coding agents see the same tools as an interactive shell, and secrets stay in vaults.

> **Status: implementation started.** The flake builds every host with the zsh layout in [`home/`](home/), the global CLI tools in [`nix/packages.nix`](nix/packages.nix), and the guard hooks in [`nix/agents.nix`](nix/agents.nix), and their tests are in; the rest of the agent configuration and the bootstrap script are not. [`docs/design.md`](docs/design.md) is the design, [`docs/adr/`](docs/adr/) records the decisions, and [`docs/verification.md`](docs/verification.md) holds the evidence behind each factual claim. Statements marked **Unverified** there still need a real machine.

![From one command to a configured host](docs/diagrams/architecture.png)

## What it sets up

| Area | Choice | Decision |
|---|---|---|
| Nix | Determinate Nix, nix-darwin on macOS, standalone home-manager on WSL2, one committed `flake.lock` | [ADR 0001](docs/adr/0001-nix-stack.md) |
| Where tools come from | Nix first: a module, then a nixpkgs package, then a Homebrew cask, then a manual install | [design: Principles](docs/design.md#principles) |
| Shell | zsh with `ZDOTDIR` under `~/.config`, PATH built in `.zshenv` so non-interactive shells and agents see the same tools | [design: Shell](docs/design.md#shell) |
| Project tools | mise in shims mode; TLA+ and Lean as flake templates | [ADR 0006](docs/adr/0006-project-layer-mise-shims.md) |
| Secrets | 1Password for personal secrets, SSH, and signing; Keeper for the work profile | [ADR 0002](docs/adr/0002-vaults-and-work-profile.md), [ADR 0005](docs/adr/0005-commit-signing.md) |
| GitHub tokens | Short-lived tokens from ghtkn; `gh` is a wrapper, never logged in | [ADR 0004](docs/adr/0004-github-auth-ghtkn.md) |
| Coding agents | Claude Code and Codex config linked from `home/`, `settings.json` generated per profile; Claude Code itself from nixpkgs, updated with `flake.lock` | [ADR 0003](docs/adr/0003-agent-config-profiles.md), [ADR 0011](docs/adr/0011-claude-code-from-nixpkgs.md) |
| Agent guardrails | Sandbox, `permissions.deny`, and a few hooks built with `writeShellApplication` | [ADR 0007](docs/adr/0007-agent-guardrails.md) |
| Shell history | atuin, with tokens kept out of anything an AI reads | [ADR 0009](docs/adr/0009-shell-history-atuin.md) |
| Working away from the desk | `personal-mac` stays awake, runs `orca serve`, and is reached over Tailscale from Orca's mobile app | [ADR 0010](docs/adr/0010-unattended-host-reachability.md) |
| Repository checks | gitleaks, `git diff --check`, a check that every tracked path stays readable to the agents, actionlint, and zizmor, in CI on every pull request; treefmt-nix and lefthook are planned | [ADR 0008](docs/adr/0008-repo-checks-lefthook-treefmt.md) |

## Hosts

| Host | What it is |
|---|---|
| `personal-mac` | The personal Mac. Also the unattended host that agents run on while the owner is away. |
| `work-mac` | The work Mac, behind a TLS-intercepting proxy. Company configuration comes from Keeper and never enters this repository. |
| `wsl` | WSL2 on a personal Windows PC. Windows-side apps (1Password, Orca, Raycast, Windows Terminal) are installed with winget by hand. |

## Install (planned)

```bash
curl -fsSL https://raw.githubusercontent.com/paveg/dotfiles/main/scripts/bootstrap.sh | bash -s -- <host>
```

`<host>` is required and is never guessed. The script installs Nix, clones this repository with ghq, switches, and stops at each step only a person can do (signing in to 1Password, Keeper, and ghtkn). Running the same command again resumes it. See [design: Bootstrap](docs/design.md#bootstrap).

## Principles

- **Agents are first-class users.** Their configuration lives here next to the shell and editor config, and the design covers it with the same tests and review.
- **Same tools for every caller.** PATH holds real executables only, so a GUI app, a non-interactive shell, and an agent resolve the same binaries.
- **Reproducible over clever.** Locked definitions, one command, and nothing that depends on guessing the machine.
- **No secrets in the repository.** Secrets come from a vault at run time; company information stays in the work profile.
- **Checked, not asserted.** Factual claims in the docs cite their source, and TLA+ models of the bootstrap and of the programs that write `settings.json` are checked by TLC in CI, each with mutants that must fail.

The full list is in [`docs/design.md`](docs/design.md#principles).

## Layout

| Path | Contents |
|---|---|
| [`docs/design.md`](docs/design.md) | Goals, architecture, bootstrap, CI, acceptance criteria, open questions |
| [`docs/adr/`](docs/adr/) | Architecture decision records |
| [`docs/verification.md`](docs/verification.md) | Evidence for every factual statement in the design |
| [`docs/diagrams/`](docs/diagrams/) | Rendered diagrams (PNG); their Excalidraw sources are not tracked |
| [`flake.nix`](flake.nix), [`hosts/`](hosts/), [`nix/`](nix/) | The flake, each host's system, login name, and own packages, the nix-darwin and home-manager modules, the agent hook builds in `nix/agents.nix`, in `nix/licenses.nix` the licences nixpkgs cannot give, and `nix/ssh_config`, which becomes `~/.ssh/config` on macOS as a store copy rather than a link |
| [`home/`](home/) | The files that land in `$HOME`, under their real names: zsh, mise, git, the reply-language hook, the guard hook sources under `home/.claude/hooks/`, which Nix builds into the store rather than links, and `home/.claude/settings.common.json`, which holds only the `Read(...)` deny rules so far and which nothing installs yet |
| [`profiles/work.example/`](profiles/work.example/) | The shape of the work profile, with placeholder values, which the tests place where `work-mac` keeps the real one; the real profile comes from Keeper and never enters this repository |
| [`spec/`](spec/) | TLA+ models checked with TLC; `check.sh` also confirms that each property catches a deliberately broken model |
| [`scripts/`](scripts/) | `pre-wipe-inventory.sh`, a read-only Markdown report of what wiping a machine would lose: uncommitted or unpushed git work, notes and agent state, history, credential locations (names and sizes only), containers, local databases, software to reinstall, files no dotfiles manage, and LaunchAgents |
| [`tests/`](tests/) | Tests that need no Nix switch; `shell.sh` starts zsh in a temporary `HOME`, `git.sh` checks which identity a repository resolves there, `ssh.sh` checks with `ssh -G` that ssh goes through the 1Password agent, `packages.sh` checks the built profile, `licenses.sh` checks the licence of everything each host installs, `reply-language.sh` checks the reply-language hook, `hooks.sh` runs each built guard hook against its fixtures under an empty PATH, `deny-paths.sh` fails when a tracked path matches an agent `Read(...)` deny rule, `pre-wipe-inventory.sh` runs the inventory script against fixture repositories in a temporary `HOME` and checks that it lists each dirty one, prints no credential contents, and changes nothing, and each has a `mutate*.sh` that breaks one condition at a time to show the checks fail, except the ones that guard the harness itself (mutants that need `/etc` to reorder the login PATH run only where it does, as on macOS) |
| [`.github/`](.github/) | CI, and Dependabot for GitHub Actions versions (`dependabot.yml`): `repo-checks.yml` runs gitleaks, the deny-path check, `git diff --check`, actionlint, and zizmor on every pull request, one job each, `spec.yml` runs `spec/check.sh`, `shell.yml` runs the shell, reply-language, git, ssh, and pre-wipe inventory tests on Linux and macOS, `hooks.yml` builds the guard hooks and runs their tests there, and their mutation tests on Linux only, `nix.yml` checks each host's licences, builds every host, and runs the package tests on what it built |
| [`AGENTS.md`](AGENTS.md) | Rules for coding agents working in this repository |

The rest of the planned layout (for example the other scripts under `scripts/`, `templates/`, and further files under `nix/` and `home/`) is in [design: Repository layout](docs/design.md#repository-layout).
