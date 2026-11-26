# The credential-read guard of docs/adr/0007-agent-guardrails.md, under a name
# that AGENTS.md allows a tracked file to carry. lib/guard.sh runs it and holds
# the tier contract.

guard_subject='The sensitive-read guard'

guard_ask_why='a hidden file or directory name next to a shell expansion, so the path that is read may be built at run time where no matcher can read it'

guard_advice='These paths hold credentials, cluster access, or shell history that must not reach an agent transcript. Take the value from its vault at run time instead: op run, ksm exec, or ghtkn exec.'

name_end='([^[:alnum:]_-]|$)'

# A name counts wherever it stands as a path segment, because no regex can
# require a path to be home-rooted: `~user/.ssh`, `//Users/x/.ssh` and
# `./../.ssh` all reach the same files. This repository's own tracked copies,
# home/.ssh/config and home/.config/ghtkn/, are therefore denied in Bash too;
# the Read tool reaches them, and the deny reason names the override.
glued_names=
guard_protect() { # <id> <ERE for the name>
  guard_rule "name-$1" deny "${guard_name_start}$2${name_end}"
  # A name that holds a dot-prefixed segment of its own is already asked about
  # by the fragment rule, so a glued variable before it needs no rule.
  if [[ $2 == '[.]'* && $2 != *'/[.]'* ]]; then
    glued_names+="${glued_names:+|}$2"
  fi
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
fragment="${guard_name_start}[.][[:alnum:]_-]"
guard_rule_both_orders fragment-expansion ask "$fragment" "$guard_expansion"
guard_rule slash-dot-expansion ask "/[.]${guard_expansion}"

# A word that starts with a dot and an expansion is a hidden name whatever
# directory it is read from, so a `cd` home needs no rule of its own
# (`cd ~ && cat .{ssh,aws}/x`, `cd; cat .{ssh,aws}/x`, `pushd "$HOME" && ...`).
# `*` and `[` stay out of the class: `.*` and `.[` start a regex or a jq filter
# far more often than a glob (`rg 'import .* from'`, `jq '.[0]'`).
word_dot_expansion='[{$`?]'
guard_rule word-dot-expansion ask "(^|[[:space:];&|<>={,])[.]${word_dot_expansion}"

# zsh, the shell of the Bash tool on the Macs, globs with parentheses too
# (`~/.s(s)h`). `(` in the expansion class would ask about every `fix(scope)`
# commit message that names a dot-file, so only a parenthesis inside a dot-word
# counts.
guard_rule dot-paren-glob ask "${guard_name_start}[.][[:alnum:]_-]*[(]"

# An unbraced variable runs into the name that follows it (`~/$x.ssh`), so the
# character before the dot is a name character and no name rule sees a name.
guard_rule glued-variable-name ask "[$][[:alnum:]_]+(${glued_names})"

guard_rule kubeconfig-expansion ask "${guard_name_start}kubeconfig.*${guard_expansion}"
guard_rule kubeconfig-expansion-reversed ask "${guard_expansion}(.*[^[:alnum:]_-])?kubeconfig"

# Committed templates, exempt where the token stands alone.
guard_exempt_tokens=(
  '.env.example'
  '.env.sample'
  '.env.template'
)
