# ADR 0013: Permission tiers for unattended runs

- Status: Accepted
- Date: 2026-11-28

## Context

Goal 9 asks that an agent started from Orca's mobile app never waits on a prompt, and the owner wants irreversible actions blocked all the same. The tiers were agreed in Linear PAV-69. Claude Code's docs (code.claude.com/docs/en/permissions, permission-modes, auto-mode-config; quoted in `verification.md`) set the constraints:

- Rules decide in the order deny, ask, allow, and the first match wins. An allow rule cannot carve an exception out of a deny rule.
- In auto mode a command that an allow, ask, or deny rule matches is decided before the classifier runs. So `autoMode.hard_deny` and `soft_deny` never see a command an allow rule approves.
- A `*` in a Bash rule matches any text, spaces included, and a `:*` at the end of a rule reads as ` *`. An allow rule with a `*` therefore also approves whatever follows its prefix: a second refspec, a force flag, another repository, or another target.
- `autoMode` is read from user settings, managed settings, and `--settings`, never from project settings. A list without `"$defaults"` replaces the built-in rules.
- By default the classifier allows a push to any branch of the working repository and blocks a merge no human approved. In an interactive session, 3 blocks in a row or 20 in total make auto mode pause and prompt; a `-p` run skips the action and keeps working.

## Decision

- All tiers go in `settings.common.json`, so they reach the generated `~/.claude/settings.json` on every host and profile. The generator is unchanged.
- `autoMode.hard_deny` and `soft_deny` hold the ticket's entries after `"$defaults"`. `soft_deny` also holds changing `gh`'s default repository and editing git remotes, which would redirect a later command that names no repository. `autoMode` stays out of the macOS drop-in: the drop-in takes only the guards and the deny list from layers the user can edit (design.md), `wsl` has no drop-in, and the classifier is the second gate, not the boundary.
- The allow list holds two reads with no argument, `gh pr checks` and `gh pr view`, exactly. With a `*` a read also takes a URL or `--repo` naming another host, which a review flagged as a way for data to leave in the URL (**Unverified**).
- The ticket's other allow entries get no rule, and the classifier decides them:
  - a merge with a pull request number needs a `*`, which also takes `--admin`, `--repo`, `--body`, `--subject` or `--body-file`, and one without a number follows `gh`'s default repository and the git remotes; `gh` refuses `--repo` without a number, so the target cannot be pinned without a `*`;
  - a push to a non-main branch needs a `*` to name the branch, which also takes a second refspec or a force flag;
  - `tests/*.sh` would run a script the agent wrote itself;
  - an `rm` rule under the scratchpad or `$TMPDIR` takes any further target.
- `permissions.deny` stays the credential reads, and `permissions.ask` stays empty for merges.
- `tests/agents.sh` decides a fixed list of commands under the generated rules with a model of the documented matcher. The two reads must resolve to allow. None of these may: a push of any kind, whatever separates its words; a merge of any form; a change to `gh`'s default repository or to a remote; a read that names a host or a repository; a script under `tests/`; and one command for each other `hard_deny` entry. The test checks the model against the docs' wildcard table, and checks that each entry, plus `"$defaults"`, is in its `autoMode` list.

## Consequences

- An unattended run reads the state of its own branch's pull request without a prompt or a classifier call. Every merge and push goes to the classifier, which applies `hard_deny` and `soft_deny` to each spelling. GitHub's required checks and a repository's ruleset on its default branch hold when the classifier misjudges.
- This does not yet make a merge prompt-free. The classifier blocks a merge no human approved unless the request names it, and in an interactive session 3 blocks in a row or 20 in total make auto mode pause and prompt, which is the stall goal 9 rules out. Whether a request such as "merge #41 once its checks pass" counts as naming the merge is the classifier's judgement and is **Unverified**. Two levers are left to the owner: an `autoMode.allow` entry for squash-merging a pull request of the working repository once its required checks pass, which the classifier still applies to each spelling and which `hard_deny` still outranks; and `permissions.denyInsteadOfPrompting`, which turns such a prompt into a denial the run can read.
- Outside auto mode, a merge, a push, a test script, and a scratch delete each prompt. A run that must not wait on a prompt runs in auto mode.
- `work-mac` gets the same rules.
- A stale write by Orca can drop `autoMode` and the allow rules from `settings.json` until the next switch, as it can the guards.

## Alternatives considered

- **`autoMode` in the drop-in as well**: the agent could not edit it, but root would take prose from a layer the user can edit, and `wsl` would still need `settings.json`. Rejected.
- **Wildcard allow rules paired with deny rules for what their `*` adds** (`git push origin pavegy/*` with a deny for a second word; `gh pr merge *--squash*` with a deny for `--admin`): tried first on this branch. A first round found a trailing `:*` reading as ` *`. Review then found a tab or an expansion between words, `--repo`, `--body`, `--subject` and `--body-file` on a merge, and `tests/*.sh` running a script the agent wrote, all still allowed. Rejected.
- **Read rules with a `*`, `gh pr checks *` and `gh pr view *`**: they also take a URL or `--repo` naming any host. Deny rules for `http*`, `--repo` and `-R` would be spelling guards again (`--repo=`, a tab), and the first would also block a pull request body that holds a link. Rejected.
- **Exact merge rules, `gh pr merge --squash` and `--squash --delete-branch`**: no `*`, but the merge follows `gh`'s default repository and the git remotes, which a command earlier in the run can change. Rejected.
- **Exact push rules, such as `git push -u origin HEAD`**: no `*`, but on a `main` checkout they push `main`. Rejected.
- **`autoMode.classifyAllShell: true`**: every shell command would go to the classifier. With no write in the allow list, it would change only the two exact reads. Not needed.
- **`ask` rules for merges or force-pushes**: a prompt stalls an unattended run. Rejected.
