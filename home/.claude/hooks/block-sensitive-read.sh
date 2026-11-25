# The credential-read guard of docs/adr/0007-agent-guardrails.md, under a name
# that AGENTS.md allows a tracked file to carry. lib/guard.sh runs it and holds
# the tier contract.

guard_subject='The sensitive-read guard'

guard_ask_why='a hidden file or directory name, or a move into the home directory, next to a shell expansion, so the path that is read may be built at run time where no matcher can read it'

guard_advice='These paths hold credentials, cluster access, or shell history that must not reach an agent transcript. Take the value from its vault at run time instead: op run, ksm exec, or ghtkn exec.'

name_end='([^[:alnum:]_-]|$)'

# A name counts wherever it stands as a path segment, because no regex can
# require a path to be home-rooted: `~user/.ssh`, `//Users/x/.ssh` and
# `./../.ssh` all reach the same files. This repository's own tracked copies,
# home/.ssh/config and home/.config/ghtkn/, are therefore denied in Bash too;
# the Read tool reaches them, and the deny reason names the override.
guard_protect() { # <id> <ERE for the name>
  guard_rule "name-$1" deny "${guard_name_start}$2${name_end}"
}

guard_protect ssh '[.]ssh'
guard_protect aws '[.]aws'
guard_protect kube '[.]kube'
guard_protect kubeconfig 'kubeconfig'
guard_protect gcloud '[.]config/gcloud'
guard_protect config-vault '[.]config/(1password|op|keeper|ksm|ghtkn)'
guard_protect dot-vault '[.](1password|keeper|ghtkn)'
guard_protect share-vault '[.]local/share/(ghtkn|atuin)'
guard_protect atuin '[.]atuin'
guard_protect claude-credentials '[.]claude/[.]credentials[.]json'
guard_protect codex-auth '[.]codex/auth[.]json'
guard_protect dotenv '[.]env'

# Shape rules. A command that names a dot-prefixed file and expands something,
# in either order and anywhere: the name the guard looks for may be the part
# that the expansion replaces (`~/.ss*`, `x=.ss; cat ~/${x}h`). A dot with no
# name character after it is a regex or a glob of its own (`rg 'import .* from'`,
# `*.{ts,tsx}`, `ls ../*`), except directly after a slash, where it is the start
# of a hidden name. The cost is that a glob after a hidden directory
# (`ls .github/workflows/*.yml`) is asked about too; measured in
# docs/verification.md.
fragment="${guard_name_start}[.][[:alnum:]_-]+"
guard_rule_both_orders fragment-expansion ask "$fragment" "$guard_expansion"
guard_rule slash-dot-expansion ask "/[.]${guard_expansion}"
guard_rule kubeconfig-expansion ask "${guard_name_start}kubeconfig.*${guard_expansion}"
guard_rule kubeconfig-expansion-reversed ask "${guard_expansion}(.*[^[:alnum:]_-])?kubeconfig"

# `cd ~` counts as naming the home directory, because what follows it needs no
# path at all (`cd ~ && cat .{ssh,aws}/x`).
home_cd='cd[[:space:]]+(~|[$][{]?home[}]?)([^[:alnum:]_/-]|$)'
guard_rule_both_orders home-cd-expansion ask "$home_cd" "$guard_expansion"

# Committed templates, exempt where the token stands alone.
guard_exempt_tokens=(
  '.env.example'
  '.env.sample'
  '.env.template'
)
