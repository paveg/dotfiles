# ADR 0006: mise in shims mode as the project-layer default

- Status: Accepted
- Date: 2026-11-25

## Context

Project tools (language runtimes, CLIs pinned per repository) were activated by shell hooks: direnv and `mise activate`, both run from `.zshrc`. A plain `zsh -c` never runs those hooks, so an agent that does not replay the interactive shell does not see the project's tools, or silently picks up a different global copy.

## Decision

- New projects declare their tools in `mise.toml`.
- `$ZDOTDIR/.zshenv` puts `$XDG_DATA_HOME/mise/shims` on PATH (mise uses `MISE_DATA_DIR`, else `$XDG_DATA_HOME/mise`). Nothing calls `mise activate`, and direnv is not used.
- Where a tool is available from several mise backends, prefer `aqua:`: mise verifies what the aqua registry declares for the tool (checksums, Cosign, Minisign, SLSA, GitHub attestations), each on by default. asdf plugins are not used: they are shell scripts that run with the user's permissions and nothing verifies them.
- Projects commit `mise.lock` (`lockfile = true` in the project's `[settings]`, or `mise lock`), which records exact versions, download URLs, and checksums. mise does not create one by default.
- Repositories that pin tools in `.aqua.yaml` use aqua, whose bin directory `$ZDOTDIR/.zshenv` also puts on PATH.
- Existing projects on devbox or a flake devShell keep them; their CLAUDE.md tells agents to run commands through `devbox run` / `nix develop -c`.
- Formal-methods tools (TLA+, Lean) are not global packages either. The flake ships `templates.tlaplus` and `templates.lean`, so a project that wants them starts with `nix flake init -t`, with versions pinned in that project. Lean's template uses `elan` and a `lean-toolchain` file, the way Lean projects pin their compiler.

## Consequences

- Every shell, interactive or not, resolves the same project tool. Measured: with only the shims directory on PATH, a non-interactive `zsh -c` ran a tool declared in a project's `mise.toml`.
- Environment variables that a hook would have set per directory (not only tools) are not applied. Projects that need them set them in their task runner or `mise.toml` tasks.
- Shims add a small dispatch cost per invocation.
- A verified lockfile pins what mise downloads, not what is already on disk. Verification also proves only who published an artifact, not that it is safe.
- aqua's own checksum verification is off by default (`checksum.enabled` or `AQUA_ENFORCE_CHECKSUM` turns it on), so repositories that keep `.aqua.yaml` should enable it in that file.

## Alternatives considered

- **TLA+ and Lean as global packages**: ready in every directory, but one version for every project and more global tools than the minimal set allows. Rejected in favour of the templates.
- **direnv / `mise activate`**: invisible to non-interactive shells. Rejected.
- **Flake devShell as the default**: needs `nix develop` or a hook to enter. Kept for projects that already use it.
- **aqua as the default**: PATH-based like shims, but oriented to CLI binaries rather than language runtimes. Kept for repositories that already pin with it.
