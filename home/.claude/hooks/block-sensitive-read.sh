# The credential-read guard of docs/adr/0007-agent-guardrails.md, under a name
# that AGENTS.md allows a tracked file to carry. lib/guard.sh runs it and holds
# the deny-only contract.

guard_subject='The sensitive-read guard'

# One list of protected names. The path patterns and the whole-command rule are
# both built from it, so a name added here cannot be missed by one of them. A
# name counts wherever it stands as a path segment, because no regex can require
# a path to be home-rooted: `~user/.ssh`, `//Users/x/.ssh` and `./../.ssh` all
# reach the same files. This repository's own tracked copies, home/.ssh/config
# and home/.config/ghtkn/, are therefore denied in Bash too; the Read tool
# reaches them, and the deny reason names the override.
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

guard_stems=("${protected_names[@]}")

name_end='([^[:alnum:]_-]|$)'

guard_patterns=()
for protected_name in "${protected_names[@]}"; do
  guard_patterns+=("${guard_name_start}${protected_name}${name_end}")
done

# A command that names a dot-prefixed file and expands something, in either
# order and anywhere: the name the guard looks for may be the part that the
# expansion replaces (`~/.ss*`, `x=.ss; cat ~/${x}h`). `cd ~` counts as naming
# the home directory, because what follows it needs no path at all
# (`cd ~ && cat .{ssh,aws}/x`). A dot with no name character after it is a
# regex or a glob of its own (`rg 'import .* from'`, `*.{ts,tsx}`, `ls ../*`),
# except directly after a slash, where it is the start of a hidden name.
# The cost is that a glob after a hidden directory (`ls .github/workflows/*.yml`)
# is denied too; measured in docs/verification.md.
fragment="${guard_name_start}[.][[:alnum:]_-]+"
home_cd='cd[[:space:]]+(~|[$][{]?home[}]?)([^[:alnum:]_/-]|$)'
guard_patterns+=(
  "${fragment}.*${guard_expansion}"
  "${guard_expansion}.*${fragment}"
  "${home_cd}.*${guard_expansion}"
  "${guard_expansion}.*${home_cd}"
  "/[.]${guard_expansion}"
)

# Committed templates, exempt where the token stands alone.
guard_exempt_tokens=(
  '.env.example'
  '.env.sample'
  '.env.template'
)

guard_advice='These paths hold credentials, cluster access, or shell history that must not reach an agent transcript. Take the value from its vault at run time instead: op run, ksm exec, or ghtkn exec.'

guard_main
