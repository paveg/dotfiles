#!/usr/bin/env bash
# Scan the whole history of the checked-out commit for secrets. Without
# --log-opts gitleaks scans every ref (git log --all), so a leak on an
# unrelated branch would fail every pull request.
# Usage: tests/gitleaks.sh [repo-dir]   (default: this checkout; needs gitleaks on PATH)
set -euo pipefail

repo_dir=$(cd "${1:-$(dirname "$0")/..}" && pwd)
gitleaks git --redact --verbose --log-opts=HEAD "$repo_dir"
