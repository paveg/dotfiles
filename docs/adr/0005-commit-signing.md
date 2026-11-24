# ADR 0005: Commit signing with 1Password, decided by measurement

- Status: Accepted, with a measurement gate
- Date: 2026-11-25

## Context

Commits are signed with an SSH key held in 1Password. By default, the 1Password SSH agent asks for approval per key and per application. An approval lasts until 1Password locks or quits; only an approval given for a set time survives a lock, and then only unlocking is asked again. Running many agents in parallel opens many terminals, so approvals could become frequent. Keeping the signing key on disk would remove prompts but contradicts the goal of keeping secrets off disk.

## Decision

- Sign with 1Password. No signing key on disk.
- Reduce prompts: unlock with Touch ID, limit offered keys with `agent.toml`, reuse SSH connections with `ControlMaster` / `ControlPersist`, never call `op` at shell start-up, and use ghtkn tokens for GitHub API work.
- Measure: run 5 agents in parallel in Orca for an hour and count 1Password prompts.
- If the count is unacceptable, switch to the fallback: agents commit unsigned in their worktrees, and the commits are re-signed before they reach a pull request. GitHub's squash merge cannot replace re-signing: with "require signed commits" on the default branch, unsigned commits on the head branch can block the squash merge even though GitHub would sign the final commit, and the documented fix is to rewrite and sign them. That change also relaxes the `--no-gpg-sign` deny rule for agent worktrees, and keeps "require signed commits" on the default branch (see ADR 0007).

## Consequences

- The signing key never leaves 1Password.
- `op-ssh-sign` needs the GUI to unlock, so headless sessions cannot sign.
- Whether each signature prompts or reuses the agent approval is not documented; the measurement answers it in practice.

## Alternatives considered

- **Signing key on disk**: no prompts, but contradicts keeping secrets off disk. Rejected.
- **Unsigned agent commits from day one**: needs a change to the `--no-gpg-sign` deny rule and to review habits before there is evidence that prompts are a problem. Deferred to the fallback.
