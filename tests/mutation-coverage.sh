#!/usr/bin/env bash
# Check what the mutation runners on tests/lib/mutate.sh declare, from their
# MUTATE_LIST output: each runner's inputs name every repository path it or a
# test script it runs reads, so a pull request that changes one runs
# the runner; the shards of a split into n hold each mutant once; a workflow
# runs each runner with MUTATE_OS on every OS one of its mutants names, so no
# mutant runs nowhere; and the shards CI runs a runner in on an OS are all n of
# them. A runner no workflow names fails.
# Usage: tests/mutation-coverage.sh [repo-dir]   (default: this checkout)
set -uo pipefail

repo_dir=$(cd "${1:-$(dirname "$0")/..}" && pwd)
checks=0
failures=0

ok() { # <name>
  checks=$((checks + 1))
  echo "ok: $1"
}

fail() { # <name> <detail>
  checks=$((checks + 1))
  failures=$((failures + 1))
  echo "FAIL: $1: $2"
}

top_level=" $(cd "$repo_dir" && echo ./* ./.github | sed 's#\./##g') "

# The repository paths <file> names, comments left out: after $repo_dir and its
# kin, as a literal path, and as a word of a `for entry in` copy loop.
paths_in() { # <file>
  local text
  # A leading space stands in for ^, which BSD grep -o handles badly.
  text=$(sed -E 's/^/ /; s/[[:space:]]#.*$//' "$1")
  {
    grep -oE '\$\{?(repo_dir|harness_dir|script_dir)\}?/[A-Za-z0-9._/-]+' <<<"$text" | sed -E 's#^[^/]*/##'
    grep -oE '[[:space:]"'"'"'=(](flake\.(nix|lock)|(nix|home|hosts|profiles|docs|scripts|tests|spec)/[A-Za-z0-9._/-]*)' <<<"$text" |
      sed -E 's#^[[:space:]"'"'"'=(]##'
    grep -E '^[[:space:]]*for entry in [^"]' <<<"$text" | sed -E 's/^[[:space:]]*for entry in //; s/;.*//' | tr ' ' '\n'
  } | sed -E 's#/+$##' | while IFS= read -r path; do
    [[ -n $path && $top_level == *" ${path%%/*} "* ]] && echo "$path"
  done | sort -u
}

covered() { # <path> <input>...
  local path=$1 input
  shift
  for input; do
    input=${input%/}
    [[ $path == "$input" || $path == "$input"/* ]] && return 0
  done
  return 1
}

# "<os> <runner> <k>/<n>" for each CI run of a runner split by OS: a step that
# runs `MUTATE_OS=<os> tests/<runner>`, or a matrix entry written on one line as
# `{ os: <os>-latest, runner: <runner>, shard: <k>/<n> }`.
invocations=$({
  grep -ohE 'MUTATE_OS=(linux|macos) tests/mutate[A-Za-z0-9-]*\.sh' "$repo_dir"/.github/workflows/*.yml |
    sed -E 's#^MUTATE_OS=([a-z]+) tests/(.*)$#\1 \2 0/1#'
  grep -ohE 'os: (ubuntu|macos)-latest, runner: mutate[A-Za-z0-9-]*\.sh, shard: [0-9]+/[0-9]+' \
    "$repo_dir"/.github/workflows/*.yml |
    sed -E 's#^os: ([a-z]+)-latest, runner: ([^,]+), shard: (.*)$#\1 \2 \3#; s#^ubuntu #linux #'
} | sort)

# Succeeds when the shards CI runs <runner> in on <os> are 0/n .. n-1/n, once each.
shards_complete() { # <os> <runner>
  local shards count want='' index
  shards=$(awk -v os="$1" -v runner="$2" '$1 == os && $2 == runner { print $3 }' <<<"$invocations")
  count=${shards%%$'\n'*}
  count=${count#*/}
  for ((index = 0; index < count; index++)); do want="$want$index/$count"$'\n'; done
  [[ -n $shards && $(sort <<<"$shards") == "$(sort <<<"${want%$'\n'}")" ]]
}

for runner in "$repo_dir"/tests/mutate*.sh; do
  name=${runner##*/}
  grep -q '^source "$repo_dir/tests/lib/mutate.sh"' "$runner" || continue
  if ! listing=$(env MUTATE_LIST=1 "$runner" 2>&1); then
    fail "list-$name" "MUTATE_LIST=1 failed: $(tail -n 3 <<<"$listing")"
    continue
  fi
  inputs=()
  while IFS= read -r input; do inputs+=("$input"); done < <(sed -n 's/^input: //p' <<<"$listing")

  missing=
  for file in "$runner" $(grep -oE '\$repo_dir/tests/[A-Za-z0-9_-]+\.sh' "$runner" | sed 's#^\$repo_dir/##' | sort -u); do
    [[ $file == /* ]] || file=$repo_dir/$file
    [[ -f $file ]] || { missing="$missing ${file#"$repo_dir"/}(absent)"; continue; }
    while IFS= read -r path; do
      covered "$path" "${inputs[@]}" || missing="$missing $path(${file##*/})"
    done < <(paths_in "$file")
  done
  if [[ -z $missing ]]; then
    ok "inputs-$name"
  else
    fail "inputs-$name" "read but not declared:$missing"
  fi

  whole=$(grep '^mutant: ' <<<"$listing" | sort)
  uneven=
  for ((count = 2; count <= 6; count++)); do
    shards=$(for ((index = 0; index < count; index++)); do
      env MUTATE_LIST=1 MUTATE_SHARD="$index/$count" "$runner" 2>&1 | grep '^mutant: '
    done | sort)
    [[ $shards == "$whole" ]] || uneven="$uneven $count"
  done
  if [[ -z $uneven ]]; then
    ok "shards-$name"
  else
    fail "shards-$name" "the shards of a split into n do not hold each mutant once, for n:$uneven"
  fi

  oses=$(awk -v runner="$name" '$2 == runner { print $1 }' <<<"$invocations" | sort -u | tr '\n' ' ')
  if [[ -z $oses ]]; then
    if grep -qE "tests/$name( |\$)" "$repo_dir"/.github/workflows/*.yml; then
      ok "run-$name"
      echo "  not split by OS: every job that runs it runs every mutant its host has"
    else
      fail "run-$name" "no workflow runs it"
    fi
    continue
  fi
  unrun='' linux=0 macos=0 both=0 declared=
  while IFS= read -r line; do
    runs_on=${line#mutant: }
    runs_on=${runs_on%%: *}
    for os in $runs_on; do
      declared="$declared$os"$'\t'"${line#mutant: "$runs_on": }"$'\n'
    done
    [[ " $runs_on " == *" linux "* ]] && linux=$((linux + 1))
    [[ " $runs_on " == *" macos "* ]] && macos=$((macos + 1))
    [[ " $runs_on " == *" linux "* && " $runs_on " == *" macos "* ]] && both=$((both + 1))
  done < <(grep '^mutant: ' <<<"$listing")
  declared_oses=$(cut -f1 <<<"$declared" | sort -u)
  for os in $(tr ' ' '\n' <<<"$oses $declared_oses" | sort -u); do
    if shards_complete "$os" "$name"; then
      ok "ci-shards-$name-$os"
    else
      fail "ci-shards-$name-$os" "the shards CI runs on $os are not 0/n to n-1/n once each: $(awk -v os="$os" -v runner="$name" '$1 == os && $2 == runner { printf "%s ", $3 }' <<<"$invocations")"
    fi
  done
  for os in $declared_oses; do
    [[ " $oses" == *" $os "* ]] && continue
    unrun="$unrun $os:"
    while IFS=$'\t' read -r declared_os description; do
      [[ $declared_os == "$os" ]] && unrun="$unrun '$description'"
    done <<<"$declared"
  done
  if [[ -z $unrun ]]; then
    ok "run-$name"
  else
    fail "run-$name" "no workflow runs it on an OS its mutants declare (it runs on: $oses); OS and the mutants for it:$unrun"
  fi
  echo "  linux $linux, macos $macos, both $both, of $(grep -c '^mutant: ' <<<"$listing"); workflows run it on: $oses"
done

echo "summary: $checks checks, $failures failed"
((failures == 0))
