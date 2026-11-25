# ADR 0005: Commit signing with 1Password, decided by measurement

- Status: Accepted, with a measurement gate
- Date: 2026-11-25

## Context

Commits are signed with an SSH key held in 1Password. By default, the 1Password SSH agent asks for approval per key and per application. An approval lasts until 1Password locks or quits; only an approval given for a set time survives a lock, and then only unlocking is asked again. Running many agents in parallel opens many terminals, so approvals could become frequent. Keeping the signing key on disk would remove prompts but contradicts the goal of keeping secrets off disk.

## Decision

- Sign with 1Password. No signing key on disk.
- Reduce prompts: unlock with Touch ID, limit offered keys with `agent.toml`, reuse SSH connections with `ControlMaster` / `ControlPersist`, never call `op` at shell start-up, and use ghtkn tokens for GitHub API work.
- Measure: run 5 agents in parallel in Orca for an hour and count 1Password prompts.
- If the count is unacceptable, switch to the fallback: agents commit unsigned in their worktrees, and the commits are re-signed before they reach a pull request. GitHub's squash merge cannot replace re-signing: with "require signed commits" on the default branch, unsigned commits on the head branch can block the squash merge even though GitHub would sign the final commit, and the documented fix is to rewrite and sign them. That change also relaxes the `--no-gpg-sign` deny rule for agent worktrees, and keeps "require signed commits" on the default branch (see ADR 0007). The same fallback covers commits made while the host is unattended and 1Password is locked.
- If re-signing at the desk becomes the bottleneck for unattended work, add a second key used only for those commits: created in the Secure Enclave (Secretive), so it cannot be exported, and registered on GitHub as a signing key only, so it cannot authenticate or push. Adopt it only after measuring that it signs while the screen is locked.

## Consequences

- The signing key never leaves 1Password.
- `op-ssh-sign` needs the GUI to unlock, so headless sessions cannot sign.
- Whether each signature prompts or reuses the agent approval is not documented; the measurement answers it in practice.

## Alternatives considered

- **Signing key on disk**: no prompts, but contradicts keeping secrets off disk. Rejected.
- **Signing key in an environment variable**: every process the agent starts inherits it, and one `env` prints it. A leaked key signs from anywhere until it is removed from GitHub. An agent socket (`SSH_AUTH_SOCK`) is different: the agent can ask for a signature but cannot read the key. Rejected.
- **Secure Enclave key registered for authentication as well as signing**: any agent on the host could then also authenticate and push with it, with no approval. Rejected in favour of the signing-only key above.
- **Commits through GitHub's API, signed by GitHub**: GraphQL `createCommitOnBranch` commits are signed by GitHub "if supported", as the authenticated user, user tokens included; REST commits are signed only when authenticated as a GitHub App or bot. Either way the agent sends file contents to the API instead of running `git commit`, so local git hooks do not run. Not pursued.
- **Unsigned agent commits from day one**: needs a change to the `--no-gpg-sign` deny rule and to review habits before there is evidence that prompts are a problem. Deferred to the fallback.
