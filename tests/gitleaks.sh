#!/usr/bin/env bash
# Scan the whole history of the checked-out commit for secrets. Without
# --log-opts gitleaks scans every ref (git log --all), so a leak on an
# unrelated branch would fail every pull request. `git log -p` prints no patch
# for a merge, which would hide a file a merge adds or a secret typed into a
# conflict resolution; --diff-merges=first-parent shows each merge against its
# first parent, so every line of every commit's tree is in some scanned patch.
# Usage: tests/gitleaks.sh [repo-dir]   (default: this checkout; needs gitleaks on PATH)
set -euo pipefail

repo_dir=$(cd "${1:-$(dirname "$0")/..}" && pwd)
gitleaks git --redact --verbose --log-opts='--diff-merges=first-parent HEAD' "$repo_dir"
