# AGENTS.md

Guidance for AI coding agents working in this repository.

## Purpose

This repository holds personal dotfiles: shell, editor, and terminal configuration, plus configuration for AI coding agents.

## Rules

- Never commit secrets, tokens, or machine-specific credentials. Reference them from a secret manager instead.
- Keep changes small: one logical change per commit, one purpose per pull request.
- Never give a tracked file a path that matches the agents' `Read` deny rules (for example one containing `secret`, `credential`, or `token`, or ending in `.key` or `_key`): no agent could read or maintain it. CI enforces this: `tests/deny-paths.sh` checks every tracked path against the `Read(...)` rules in `home/.claude/settings.common.json`.
- Document any new top-level directory in `README.md` in the same change that adds it.
