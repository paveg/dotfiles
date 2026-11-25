# The credential-read guard of docs/adr/0007-agent-guardrails.md, under a name
# that AGENTS.md allows a tracked file to carry. lib/guard.sh runs it and holds
# the deny-only contract.

guard_subject='The sensitive-read guard'

# One list of protected names, which every pattern below is built from, so that
# a name added here cannot be missed by one of them. A name counts wherever it
# stands as a path segment, because no regex can require a path to be
# home-rooted: `~user/.ssh`,
# `//Users/x/.ssh` and `./../.ssh` all reach the same files. This repository's
# own tracked copies, home/.ssh/config and home/.config/ghtkn/, are therefore
# denied in Bash too; the Read tool reaches them, and the deny reason names the
# override.
protected_names=(
  '[.]ssh'
  '[.]aws'
  '[.]kube'
  'kubeconfig'
  '[.]config/gcloud'
  '[.]config/(1password|op|keeper|ksm|ghtkn)'
  '[.](1password|keeper|ghtkn)'
  '[.]local/share/(ghtkn|atuin)'
  '[.]atuin'
  '[.]claude/[.]credentials[.]json'
  '[.]codex/auth[.]json'
  '[.]env'
)

name_end='([^[:alnum:]_-]|$)'

guard_patterns=()
for protected_name in "${protected_names[@]}"; do
  guard_patterns+=("${guard_name_start}${protected_name}${name_end}")
done

# An expansion character inside a dot-prefixed path segment, as in `~/.ss*` or
# `"$HOME"/.{ssh,aws}`: there is no name left to compare, and expanding one
# needs a shell. Globbing inside a directory (src/*.ts, .github/workflows/*.yml)
# is untouched, because the character has to follow the dot's own name.
guard_patterns+=("${guard_name_start}[.][[:alnum:]_-]*${guard_unresolvable}")

# Committed templates, compared as whole tokens so that .env.exam stays denied.
guard_exempt_suffixes=(
  '.env.example'
  '.env.sample'
  '.env.template'
)

guard_advice='These paths hold credentials, cluster access, or shell history that must not reach an agent transcript. Take the value from its vault at run time instead: op run, ksm exec, or ghtkn exec.'

guard_main
