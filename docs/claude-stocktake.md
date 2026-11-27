# Stock-take of the previous `~/.claude` entries

- Status: Proposal (PAV-46). Nothing listed here has been copied into this repository.
- Date: 2026-11-27

The previous setup deployed `~/.claude` from the chezmoi source of `paveg/dots` (`home/dot_claude/`). This document lists every entry it managed and proposes what happens to each under ADR 0003's profiles (`common`, `personal`, `work`). The owner decides; the reasons below are evidence, so a row can be accepted or overruled without re-reading the entry.

## How the evidence was gathered

- **Inventory**: `chezmoi managed`, filtered to `.claude`, compared with `home/dot_claude/` in the chezmoi source clone (HEAD `b285ce4`, 2026-11-26). The 27 skill directories hold 81 files tracked in git (`git ls-files`; an 82nd, `skills/.gitkeep`, is not deployed); chezmoi adds 4 more from an external archive (`writing-proofread/scripts/yomiyasu/`).
- **Last change, commits**: `git log --follow` per file (per `SKILL.md` for a skill), leaving out `228e86c` ("isolate chezmoi source root"), which moved files and made one-line edits to `settings.json.tmpl` and `empirical-prompt-tuning/SKILL.md`. `e61eeb2` (2026-10-08, "tune skills, agents, and harness for Opus 5.5 / Sonnet 5.5 / Fable 5.1") touched many entries at once, so a 2026-10-08 date says little about that entry alone.
- **Referenced by**: other files in `home/dot_claude/` that name the entry by its file or skill name. A `settings.json.tmpl` hit that is only a `skillOverrides` entry is listed as "off", not as a use. No count is given where the name is a common word.
- **Profile**: the previous `.chezmoiignore` left six skills out when `business_use` was set (block "Personal-only skills"). Those are `personal`; everything else was deployed on both kinds of machine, so it is `common` unless the row says otherwise.
- **Disabled**: the previous `settings.json.tmpl` sets `skillOverrides` to `"off"` for `browser-e2e-test`, `interrupt`, `ipo-decision`, `issue-ship`, `learning-primer`, and `x-post-craft`.
- **Runtimes**: `nix/packages.nix` has no `python3`, `uv`, `node`, `pnpm`, `npx`, `textlint`, or `codex`, and design.md ("Packages") says "No other language runtimes". A row that needs one says so.
- **Plugins**: no managed skill or agent has the same name as a skill or agent in an installed plugin (`~/.claude/plugins/cache`). Overlaps in purpose are named per row. Plugin-provided entries are not listed.
- **Hooks**: from ADR 0007, design.md ("Guardrails"), `docs/verification.md` ("Hook need across repositories"), and what `home/.claude/hooks/` already holds.

Proposal values: **keep** (bring into `home/.claude/` or the profile named), **drop**, **move** (to the `.claude/` of the projects that need it). "Flag" marks an entry that must not reach this public repository as it is; the flag table at the end lists them.

## Skills

Source paths are relative to `home/dot_claude/` in `paveg/dots`. Target: `home/.claude/skills/<profile>/<name>/`.

| Name | Source | Purpose (own description) | Proposal | Profile | Reason |
|---|---|---|---|---|---|
| `adversarial-review` | `skills/adversarial-review/` | Break a change before it ships: extract a diff's claims, run each through its decisive check, return a PASS/FAIL table | keep | common | Referenced by `rules/workflow.md` and `issue-ship`; last change 2026-10-20 |
| `browser-e2e-test` | `skills/browser-e2e-test/` | E2E testing of web apps through Chrome, filing GitHub Issues for bugs | drop | — | Off in `skillOverrides`; no other entry references it |
| `claude-md-layout` | `skills/claude-md-layout/` | Decide which directory-level CLAUDE.md holds which convention | keep | common | Consumer named in `references/model-profiles/README.md`; referenced by `empirical-prompt-tuning`; last change 2026-07-26 |
| `code-rationale` | `skills/code-rationale/` | Trace why code has its shape from every evidence source; cited, confidence-tiered answer | drop | — | Adapted from pstack `why` (its own header says so); the pstack plugin is installed and ships `why`, and ADR 0003 leaves third-party skills to marketplaces. Mixed: last change 2026-11-25, and kept `rules/repo-notes.md` names it. **Flag**: its `LICENSE` names a person (MIT copyright holder) |
| `codex-subagent` | `skills/codex-subagent/` | Delegate a bounded task to the local Codex CLI and verify the result | keep | common | Named by `rules/workflow.md` for when an independent model's read is the point, and the only Codex mechanism under `home/dot_claude`. Needs `codex`, which is not in `nix/packages.nix` |
| `context-diet` | `skills/context-diet/` | Cut what skills, rules, and CLAUDE.md cost in context without losing behaviour | keep | common | Consumer named in `model-profiles/README.md`. `scripts/measure.py` runs with `python3`, not in `nix/packages.nix` |
| `empirical-prompt-tuning` | `skills/empirical-prompt-tuning/` | Improve agent-facing instructions by having a bias-free executor run them | keep | common | 6 commits, last 2026-10-08; consumer named in `model-profiles/README.md`. **Flag**: tells the agent to edit the chezmoi source path, which does not exist under Nix |
| `equity-decision` | `skills/equity-decision/` | One-page purchase memo for a US or JP stock | keep | personal | Personal-only in `.chezmoiignore`. Scripts run with `uv`, not in `nix/packages.nix`. **Flag**: `scripts/fetch_edgar.py` carries the owner's email address, and four files carry a literal 1Password item reference |
| `excalidraw-diagram` | `skills/excalidraw-diagram/` | Create `.excalidraw` diagrams and render them to PNG to check them | keep | common | Last change 2026-11-02. Needs `node`, `pnpm`, and Chrome, none in `nix/packages.nix`; the renderer was built by a chezmoi `run_onchange` script that has no Nix counterpart yet. **Flag**: SKILL.md says `chezmoi apply` builds it |
| `grill-me` | `skills/grill-me/` | Round-based interview that settles a plan and writes it down as an ADR or design doc | keep | common | Last change 2026-11-01; no other entry references it. Similar in purpose to installed plugin skills (pstack `interrogate`, superpowers `brainstorming`); not compared in detail |
| `interrupt` | `skills/interrupt/` | Hand a small task to a background agent in an isolated worktree | drop | — | Off in `skillOverrides`; no other entry references it |
| `ios-submission-review` | `skills/ios-submission-review/` | Pre-submission App Store rejection scan | keep | personal | Personal-only in `.chezmoiignore` |
| `ipo-decision` | `skills/ipo-decision/` | IPO subscription-decision memo for a JP pre-listing IPO | drop | — | Off in `skillOverrides`; personal-only in `.chezmoiignore`; runs `equity-decision`'s scripts. Only `references/skill-naming.md` mentions it, as a naming example |
| `issue-ship` | `skills/issue-ship/` | Ship a GitHub Issue end-to-end: worktree subagent, PR, CI through merge | drop | — | Off in `skillOverrides`. Mixed: kept `rules/workflow.md` and `adversarial-review` still name it ("issue-ship's adversarial-review loop"), so dropping it means editing both |
| `learning-primer` | `skills/learning-primer/` | Research a topic and write a disposable GFM + mermaid primer outside the repo | drop | — | Off in `skillOverrides`. Mixed: last change 2026-11-25, and kept `rules/repo-notes.md` defines where its output goes |
| `loop-design` | `skills/loop-design/` | Design a recurring or autonomous agent loop before running it | keep | common | Points to `rules/loop-engineering.md` and `pr-monitor`; no other entry references it; last change 2026-10-08 |
| `pentest-parallel-prs` | `skills/pentest-parallel-prs/` | Attacker-perspective security review shipped as one PR per fix | keep | common | 5 commits, last 2026-10-08; referenced by `adversarial-review` |
| `pr-description` | `skills/pr-description/` | Rewrite a PR description into a fixed layout with a verification table | keep | common | Last change 2026-10-08; depends on kept `rules/gh-pr-body.md` and `rules/japanese-writing.md`. **Flag**: names the auto-generated block marker of a work-org plugin |
| `pr-monitor` | `skills/pr-monitor/` | Watch a PR until CI is green and threads resolve; optional auto-fix | keep | common | Referenced by `rules/loop-engineering.md`, `loop-design`, and `issue-ship`. Mixed: last change 2026-07-26, and Claude Code now has a built-in `/steward` that watches the branch's PR through merge |
| `prevent-recurrence` | `skills/prevent-recurrence/` | Make a recurring mistake impossible to repeat, with a check that fails on a past occurrence | keep | common | `rules/workflow.md` tells the agent to suggest it when a correction repeats |
| `trend-arbitrage` | `skills/trend-arbitrage/` | Find content or product opportunities with high demand and low supply | keep | personal | Personal-only in `.chezmoiignore` |
| `ui-design-standards` | `skills/ui-design-standards/` | UI quality bar: spec fidelity, design tokens, interaction states, accessibility | keep | common | Last change 2026-10-08; no other entry references it. Similar in topic to installed plugin skills (`frontend-design`, `wcag-audit-patterns`); not compared in detail |
| `verify-doc-claims` | `skills/verify-doc-claims/` | Table a document's factual claims and force each row to cite evidence | keep | common | Referenced by `adversarial-review` |
| `writing-proofread` | `skills/writing-proofread/` | Proofread Japanese prose for AI smell, rhythm, and naturalness | keep | common | 13 commits, last 2026-11-13; referenced by both Japanese reviewer agents, `rules/japanese-writing.md`, and `references/japanese-writing/norms.md`. Needs `uv`, `python3`, and `npx textlint`, none in `nix/packages.nix`. Its yomiyasu scripts came from a chezmoi external (v3.1.0); the installed yomiyasu plugin is 2.5.0. **Flag**: `scripts/NOTICE.md` names upstream authors (MIT copyright holders, required by the licence) and points at `.chezmoiexternal.toml`; `assets/prh.yml` names the owner's personal blog |
| `writing` | `skills/writing/` | Write or revise Japanese documents of any genre through one entry point | keep | common | `writing-proofread` runs as its proofreading phase; last change 2026-08-19. No reference count: the name is a common word. **Flag**: its description and three reference files name the owner's personal blog |
| `x-post-craft` | `skills/x-post-craft/` | Write X/Twitter posts tuned to the published ranking algorithm | drop | — | Off in `skillOverrides`; personal-only in `.chezmoiignore`; no other entry references it |
| `zero-cost-scaling` | `skills/zero-cost-scaling/` | Zero-cost scaling patterns for indie web apps that may go viral | keep | personal | Personal-only in `.chezmoiignore`; no other entry references it |

## Rules

Source paths are relative to `home/dot_claude/`. Target: `home/.claude/rules/`, which ADR 0003 links as a whole for every profile, so a kept rule is `common`.

| Name | Source | Purpose (own heading or first line) | Proposal | Profile | Reason |
|---|---|---|---|---|---|
| `browser-automation.md` | `rules/browser-automation.md` | Browser automation: click-and-type, read back every field | keep | common | Excluded from the always-loaded set (`claudeMdExcludes`) and injected by the browser hook, which ADR 0007 keeps; about 1,300 injections (`verification.md`) |
| `chezmoi.md` | `rules/chezmoi.md` | Confirm with the user before `chezmoi apply` | drop | — | design.md replaces chezmoi; its `paths:` glob (`**/.local/share/chezmoi/**`) matches nothing under Nix. **Flag**: machine-specific path |
| `db-safety.md` | `rules/db-safety.md` | Judgement the destructive-database guard cannot make | keep | common | The guard is kept (ADR 0007), and 14 of 70 repositories carry drizzle configs or SQL migrations (`verification.md`). Its description of the hook ("matches known literal patterns") predates the new guard's `ask` tier and needs rewording |
| `design-decision-visibility.md` | `rules/design-decision-visibility.md` | Make better-practice choices visible instead of applying them silently | keep | common | Always loaded; no overlap found |
| `development-principles.md` | `rules/development-principles.md` | Simplicity ladder, comments, readability, command legibility | keep | common | 15 commits, last 2026-10-08; the comment-rot checker enforces its comment section |
| `drizzle.md` | `rules/drizzle.md` | Drizzle ORM conventions (timestamps and more) | move | — | The owner's own `harness-meta.md`: "Project-specific rules (framework, ORM, deployment target) belong in the project's CLAUDE.md". Mixed: already path-scoped, and 14 repositories carry drizzle configs or SQL migrations |
| `english-proofreading.md` | `rules/english-proofreading.md` | Correct the user's English in 1–3 points | keep | common | 3 lines; no overlap found |
| `gh-pr-body.md` | `rules/gh-pr-body.md` | Never backslash-escape backticks in a `gh pr` body | keep | common | Excluded from the always-loaded set and injected by the PR-body hook (ADR 0007 keeps it; 148 injections in `verification.md`) |
| `harness-engineering.md` | `rules/harness-engineering.md` | Generator–evaluator separation, review discipline, oscillation guard | keep | common | 10 commits; referenced by six entries (skills, a rule, a model profile) |
| `harness-meta.md` | `rules/harness-meta.md` | Rule hygiene, escalation ladder, TDD for rules and hooks | keep | common | Referenced by `context-diet` and `loop-engineering.md`. **Flag**: its `paths:` includes `**/dot_claude/**`, the chezmoi source naming |
| `japanese-writing.md` | `rules/japanese-writing.md` | Japanese prose: particles, active voice, no AI smell | keep | common | Points to `references/japanese-writing/norms.md`; 450 Japanese-writing injections in `verification.md` |
| `loop-engineering.md` | `rules/loop-engineering.md` | Conventions for autonomous or long-running loops | keep | common | Path-scoped (`STATE.md`, `LOOP.md`, run logs); last change 2026-11-25; used by `loop-design` |
| `markdown-formatting.md` | `rules/markdown-formatting.md` | Markdown: no typed numerals, no hard wrap, mermaid only in artifacts | keep | common | 7 commits; referenced by `gh-pr-body.md` and `writing` |
| `pr-size.md` | `rules/pr-size.md` | ≤ 300 effective LOC and one purpose per PR | keep | common | Always loaded; matches AGENTS.md's "one purpose per pull request" |
| `react.md` | `rules/react.md` | React conventions (avoid `useEffect`, and more) | move | — | Same `harness-meta.md` rule as `drizzle.md`. Already path-scoped to `*.tsx`/`*.jsx`; the number of repositories that need it was not counted |
| `repo-notes.md` | `rules/repo-notes.md` | Where the user's local note pile lives and when to write to it | keep | common | 7 commits, last 2026-11-25; the previous settings add the note directory to `additionalDirectories`. Names `code-rationale` and `learning-primer`, both proposed for dropping |
| `schema-design.md` | `rules/schema-design.md` | Agreement gate and shape principles for durable shapes | keep | common | 1 commit; no overlap found |
| `tdd.md` | `rules/tdd.md` | Test-driven development for code files | keep | common | Path-scoped to source files. Overlaps superpowers `test-driven-development` and pstack `tdd` (both installed), but the previous settings enable superpowers only on the personal side |
| `workflow.md` | `rules/workflow.md` | Planning, delegation, subagent-driven implementation, verification | keep | common | 18 commits, the most of any rule; the global CLAUDE.md names it. Names `issue-ship`, proposed for dropping |

## References

Source paths are relative to `home/dot_claude/`. Target: `home/.claude/references/`.

| Name | Source | Purpose (own heading) | Proposal | Profile | Reason |
|---|---|---|---|---|---|
| `japanese-writing/norms.md` | `references/japanese-writing/norms.md` | Full Japanese writing norms | keep | common | Named by both Japanese injector hooks, `rules/japanese-writing.md`, `writing`, and `writing-proofread`. **Flag**: names an upstream author's handle (attribution for a distilled item) |
| `model-profiles/README.md` | `references/model-profiles/README.md` | How per-model prompting profiles work and who consumes them | keep | common | Defines the contract `claude-md-layout`, `context-diet`, and `empirical-prompt-tuning` load |
| `model-profiles/_template.md` | `references/model-profiles/_template.md` | Template for a new model profile | keep | common | The README's update procedure copies it |
| `model-profiles/fable-5-1.md` | `references/model-profiles/fable-5-1.md` | Fable 5.1 prompting profile | drop | — | Superseded by `fable-5-2.md` in the same family; no entry references it |
| `model-profiles/fable-5-2.md` | `references/model-profiles/fable-5-2.md` | Fable 5.2 prompting profile | keep | common | `skeptic` pins `model: fable`; referenced by `sonnet-5-5.md` |
| `model-profiles/opus-4-8.md` | `references/model-profiles/opus-4-8.md` | Opus 4.8 prompting profile | drop | — | No agent pins it and no entry references it; `_template.md` uses its model id only as a format example |
| `model-profiles/opus-5.md` | `references/model-profiles/opus-5.md` | Opus 5 prompting profile | keep | common | `opus-5-5.md` is a delta on it ("every Opus 5 row not contradicted below still applies", line 7), so dropping it breaks the kept profile. Fold its rows into `opus-5-5.md` and drop it then, or keep both |
| `model-profiles/opus-5-5.md` | `references/model-profiles/opus-5-5.md` | Opus 5.5 prompting profile | keep | common | Profile of the current main-session model; referenced by `fable-5-2.md` |
| `model-profiles/sonnet-5-5.md` | `references/model-profiles/sonnet-5-5.md` | Sonnet 5.5 prompting profile | keep | common | Five of the six agents pin `model: sonnet` |
| `skill-naming.md` | `references/skill-naming.md` | Skill naming convention | keep | common | No entry references it (weak); last change 2026-08-19. Its table names `ipo-decision`, proposed for dropping |

## Agents

Source paths are relative to `home/dot_claude/`. Target: `home/.claude/agents/`. Five are named in `rules/workflow.md`; the sixth, `wording-reviewer`, only in `writing-proofread`, and none shares a name with a plugin agent.

| Name | Source | Purpose (own description) | Proposal | Profile | Reason |
|---|---|---|---|---|---|
| `comment-reviewer.md` | `agents/comment-reviewer.md` | Judge every added comment and suppression in a diff | keep | common | Named in `workflow.md`'s review stage. Overlaps pr-review-toolkit `comment-analyzer` and pstack `comment-sicko` (installed); the previous personal settings set pr-review-toolkit to `false` |
| `implementer.md` | `agents/implementer.md` | Implementation worker for a settled plan | keep | common | Referenced by `workflow.md`, `spec-reviewer`, `interrupt`, `issue-ship`, and two model-profile files |
| `prose-reviewer.md` | `agents/prose-reviewer.md` | Japanese prose reviewer for a diff; runs both linters | keep | common | Needs `writing-proofread`'s scripts through `uv` and `python3 -I`, not in `nix/packages.nix`. **Flag**: its description says chezmoi fetches the yomiyasu scripts |
| `skeptic.md` | `agents/skeptic.md` | Adversarial claim verifier | keep | common | Referenced by `workflow.md`, `adversarial-review`, `code-rationale`, `context-diet`, and three model profiles; `workflow.md` names it the strongest evaluator |
| `spec-reviewer.md` | `agents/spec-reviewer.md` | First-pass spec-compliance screen of implementer output | keep | common | Referenced by `workflow.md`, `adversarial-review`, `issue-ship`, and two model profiles |
| `wording-reviewer.md` | `agents/wording-reviewer.md` | Japanese word-level naturalness reviewer | keep | common | Dispatched by `writing-proofread`; same `uv` and `python3` need as `prose-reviewer`. **Flag**: names an upstream author's handle (attribution for distilled tests) |

## Hooks

Source paths are relative to `home/dot_claude/`. ADR 0007 decides each one; hooks are built into the store, not linked. Three are already in `home/.claude/hooks/`.

| Name | Source | Purpose (own header) | Proposal | Profile | Reason |
|---|---|---|---|---|---|
| `block-credential-read.sh` | `hooks/executable_block-credential-read.sh` | Deny Bash commands that reference credential paths | keep | common | ADR 0007: kept until the sandbox's `denyRead` is measured; already ported as `home/.claude/hooks/block-sensitive-read.sh`. Only its three header lines were read (by the inventory script); its body was not opened because its name contains "credential". Classified from ADR 0007 and design.md |
| `block-destructive-db.sh` | `hooks/executable_block-destructive-db.sh` | Deny destructive database operations | keep | common | ADR 0007: kept with `onFailure: "block"`; already ported. 5 deny lines in 3 projects (`verification.md`) |
| `block-rot-comments.py` | `hooks/executable_block-rot-comments.py` | Block code comments that match rot-prone patterns | keep | common | ADR 0007: kept as a checker, rewritten from Python; not ported yet. 13 deny lines in 6 projects |
| `block-unsigned-commits.sh` | `hooks/executable_block-unsigned-commits.sh` | Deny git commands that skip signing | drop | — | ADR 0007: removed, replaced by deny rules and GitHub's "require signed commits". Those deny rules (`--no-gpg-sign`, `-c commit.gpgsign=false`, `git config … commit.gpgsign`) are not in `settings.common.json` yet |
| `browser-inject.sh` | `hooks/executable_browser-inject.sh` | Inject `browser-automation.md` for `mcp__claude-in-chrome__*` calls | keep | common | ADR 0007: injector, kept; not ported yet |
| `check-reply-language.sh` | `hooks/executable_check-reply-language.sh` | Send Claude back when a reply to a Japanese message is in English | keep | common | design.md "Guardrails": added; already ported |
| `gh-pr-inject.sh` | `hooks/executable_gh-pr-inject.sh` | Inject `gh-pr-body.md` for `gh pr create` / `gh pr edit` | keep | common | ADR 0007: injector, kept; not ported yet. 148 injections |
| `japanese-writing-inject.sh` | `hooks/executable_japanese-writing-inject.sh` | Inject the norms pointer when a `.md` with Japanese is written | keep | common | ADR 0007: injector, kept; not ported yet. 450 injections |

Two hook entries in the previous settings are not files: the `type: "agent"` Stop hook (unaddressed-request check), which ADR 0007 keeps as a prompt in `settings.common.json`, and herdr's `herdr-agent-state.sh`, which herdr owns and the generator carries over only if herdr is adopted.

## Other files

| Name | Purpose | Source | Proposal | Profile | Reason |
|---|---|---|---|---|---|
| `CLAUDE.md` | Global instructions: reply language, pointer to `workflow.md` | `home/dot_claude/CLAUDE.md` | keep | common | ADR 0003 links it, and the same file becomes `~/.codex/AGENTS.md`. design.md ("Environment facts for agents") adds four facts it does not hold yet |
| `statusline.sh` | One- or two-line status from the session JSON plus a cached `git status` | `home/dot_claude/executable_statusline.sh` | keep | common | ADR 0003 links it. The external commands it names are `cat`, `jq`, `git`, `awk`, and `date`; `jq` and `git` are in `nix/packages.nix` |
| `settings.json`, common part | Advisor model, auto-mode environment, permissions, status line, hook registration, `claudeMdExcludes`, worktree base | `home/dot_claude/settings.json.tmpl` | keep | common | Goes into `settings.common.json` (ADR 0003). That file so far holds the same `Read(...)` deny rules as the previous one and nothing else; the remaining rules are rewritten to design.md's "Permission rules" forms, not carried over. Its `soft_deny` entry for `chezmoi init` has no use under Nix. **Flag**: `additionalDirectories` and the herdr hook are written with the chezmoi home-directory variable |
| `settings.json`, personal part | Personal plugins, the `rust-skills` marketplace, `skipDangerousModePermissionPrompt` | `home/dot_claude/settings.json.tmpl` | keep | personal | Goes into `settings.personal.json`. The previous file sets both `skipDangerousModePermissionPrompt: true` (personal) and `disableBypassPermissionsMode: "disable"` (common), and design.md keeps only the latter; whether the former still does anything was not checked. `skillOverrides` is not personal: it sits outside every `business_use` conditional, so it applied on both machine kinds and belongs to the common part. Of its 18 entries, 6 turn off managed skills and 12 turn off unmanaged or plugin skills |
| `settings.json`, work part | Internal API endpoint, internal marketplaces, work plugins, deny rules for cloud, cluster, and infrastructure CLIs | `home/dot_claude/settings.json.tmpl` | keep | work | **Flag**: names the work org, an internal hostname, and internal marketplaces. Goes to `~/.config/dots-work/claude/settings.work.json` (untracked, Keeper), never to this repository; only its shape belongs in `profiles/work.example/` |
| `mcp-servers.json`, personal part | textlint and 1Password MCP servers | `home/dot_claude/mcp-servers.json.tmpl` | keep | personal | Needs `textlint`, which is not in `nix/packages.nix` |
| `mcp-servers.json`, work part | Internal MCP servers | `home/dot_claude/mcp-servers.json.tmpl` | keep | work | **Flag**: names the work org through its tool prefix and holds machine-specific paths. Goes to `~/.config/dots-work/claude/mcp.work.json` (design.md "Repository layout") |

## Entries that must not go to the public repository as they are

| Entry | What it carries | Before it can be published |
|---|---|---|
| `settings.json.tmpl` (work part) | Work org name, internal hostname, internal marketplace and plugin names | Work profile only; never published |
| `mcp-servers.json.tmpl` (work part) | Work org tool prefix; paths under the home directory (tool manager, CA bundle) | Work profile only; never published |
| `equity-decision` | The owner's email address (in a User-Agent string); a literal 1Password item reference in four files | Read both from the environment or a secret manager |
| `code-rationale` | A person's name (MIT copyright line) | Moot if dropped; the licence requires the line if kept |
| `settings.json.tmpl` (common part) | Paths written with the chezmoi home-directory variable (`additionalDirectories`, the herdr hook) | Generate the paths at activation |
| `pr-description` | The auto-generated block marker of a work-org plugin | Generalise the example |
| `writing-proofread` | Upstream authors' handles (MIT copyright lines in `NOTICE.md`); `.chezmoiexternal.toml` paths; the owner's blog name in `assets/prh.yml` | The licence requires the names; replace the chezmoi paths with the Nix fetch |
| `wording-reviewer.md`, `japanese-writing/norms.md` | Upstream authors' handles in attribution lines | Attribution for MIT sources; keeping it is the owner's call |
| `writing` | The owner's personal blog name in its description and three reference files | The owner's call; not a secret |
| `empirical-prompt-tuning` | The chezmoi source path | Rewrite for this repository's layout |
| `excalidraw-diagram` | `chezmoi apply` as the build step | Rewrite once the renderer build exists under Nix |
| `prose-reviewer.md` | "chezmoi fetches" in its description | Rewrite with the yomiyasu fetch |
| `harness-meta.md` | `**/dot_claude/**` path glob | Replace with this repository's path |
| `chezmoi.md` | The chezmoi source path | Moot if dropped |

## Left out

- **Plugin-provided**: everything under `~/.claude/plugins`.
- **Live `~/.claude/skills/` entries that chezmoi never managed**: `gh-stack` (installed by a chezmoi `gh skill` script, not a managed file); `orca-cli`, `orca-computer-use`, `orca-linear`, `orchestration` (Orca's skills); the Cloudflare skills that match no installed plugin (`basin`, `cf-cli`, `gateway-workers`, `k2`, `nextjs-on-cloudflare`, `sandbox-sdk`, `workers-profiling`); and `feature`, `japanese-legal-proofreader`, `seo-affiliate-article`, `synced`, whose origin was not found.
- **Outside `~/.claude`**: `home/dot_codex/` (Codex `AGENTS.md` and rules) and `home/dot_agents/` (a symlink to the skills directory).

## Summary

Rows: 77 (27 skills, 19 rules, 10 references, 6 agents, 8 hooks, 7 rows for 4 other files). Counts are of the proposals above, before the owner's decisions at the end.

| Proposal | Skills | Rules | References | Agents | Hooks | Other | Total |
|---|---|---|---|---|---|---|---|
| keep | 20 (16 common, 4 personal) | 16 | 8 | 6 | 7 | 7 (3 common, 2 personal, 2 work) | 64 |
| drop | 7 | 1 | 2 | 0 | 1 | 0 | 11 |
| move | 0 | 2 | 0 | 0 | 0 | 0 | 2 |

The five decisions where the evidence is mixed:

1. **`issue-ship` and `learning-primer`**: both are off in `skillOverrides`, yet kept entries name them (`workflow.md` and `adversarial-review` name `issue-ship`; `repo-notes.md` defines `learning-primer`'s output). `learning-primer` changed as recently as 2026-11-25. Drop both and edit those three files, or keep them and drop the override.
2. **`code-rationale`**: a local adaptation of pstack `why`, and pstack is installed. Dropping it follows ADR 0003's third-party rule, but the adaptation changed on 2026-11-25 and `repo-notes.md` relies on it.
3. **`drizzle.md` and `react.md`**: `harness-meta.md` sends project-specific rules to the project, but both are already path-scoped (they cost nothing outside matching files), and 14 repositories carry drizzle configs or SQL migrations. Moving means copying them into each of those repositories.
4. **Runtimes for kept skills and agents**: `writing-proofread`, `prose-reviewer`, `wording-reviewer`, `context-diet`, `equity-decision`, and `excalidraw-diagram` need `python3`, `uv`, `node`, `pnpm`, or `npx`, and `codex-subagent` needs `codex`; `nix/packages.nix` has none, and design.md rules out other language runtimes. Choose between adding them (globally or per skill), changing the skills, or dropping them. The yomiyasu scripts also need a new source: a Nix fetch of v3.1.0, or the installed plugin (2.5.0).
5. **`pr-monitor`**: two kept entries (`loop-engineering.md`, `loop-design`) and `issue-ship`, which is proposed for dropping, reference it, but its last change is 2026-07-26, and the built-in `/steward` now watches a PR through merge. Keep it, or drop it and point `loop-engineering.md` and `loop-design` at `/steward`.

Not classified: `feature`, `japanese-legal-proofreader`, `seo-affiliate-article`, and `synced` in the live skills directory, which have neither a chezmoi source nor a plugin; and `block-credential-read.sh` was classified from ADR 0007 without its body being read.

## Owner decisions (2026-11-27)

These override the proposals above where they differ.

1. `issue-ship`: drop. Claude Code's `/ship` covers commit, PR, review and watching through merge. `learning-primer`: keep, profile `common`, after a check that it does not call `issue-ship`.
2. pstack is adopted in full, and Cursor is not used. Its Claude Code adapter maps or skips the Cursor-only steps. Where a pstack rule and the owner's rules conflict, the owner's rule wins, written once in a common rule (for example, push and PR confirmation in `workflow.md` against `poteto-mode`'s autonomy). Local skills that pstack or Claude Code now cover are dropped: `code-rationale` (pstack `why`) and `pr-monitor` (`/steward`). Whether `adversarial-review` gives way to pstack `interrogate` is still open. Work-only MCP servers and internal reference targets go in the untracked work profile.
3. `drizzle.md` and `react.md` become templates in this repository, copied into a project's own `.claude/rules/` by an explicit command when the project is set up. They are not linked globally.
4. Language runtimes stay narrow. Nix installs the version managers (mise, uv, rustup, elan). mise holds a global default and per-project versions for go, node, pnpm, deno and ruby. Swift comes from Xcode. MoonBit uses its official installer, and its licence must be checked before it is installed on `work-mac`. Python is used through `uv` for the skills that need it. This replaces design.md's "No other language runtimes", which an ADR records.
5. `pr-monitor`: drop, because `/steward` replaces it. Note: `/steward` is not a drop-in equivalent. It watches in the current session and starts no background watch, while `pr-monitor` watched asynchronously so the session could keep working (code.claude.com/docs/en/ship-command, by a review agent).
