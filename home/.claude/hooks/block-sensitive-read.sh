# The credential-read guard of docs/adr/0007-agent-guardrails.md, under a name
# that AGENTS.md allows a tracked file to carry. lib/guard.sh runs it and holds
# the deny-only contract.

guard_subject='The sensitive-read guard'

# A credential name counts wherever it stands as a path segment, because no
# regex can require a path to be home-rooted: `~user/.ssh`, `//Users/x/.ssh`
# and `./../.ssh` all reach the same files. This repository's own tracked
# copies, home/.ssh/config and home/.config/ghtkn/, are therefore denied in
# Bash too; the Read tool reaches them, and the deny reason names the override.
name_end='([^[:alnum:]_.-]|$)'

# ERE has no negative lookahead, so ".env with a suffix other than a committed
# template" is spelled as a mismatch against each exempt word. The three start
# with different letters, so one branch each covers it. A suffix that only
# begins with one (.env.examples) is exempt, and a truncated one (.env.e)
# passes; both are template names rather than places a secret is kept.
other_suffix='([^est]'
other_suffix+='|e([^x]|x([^a]|a([^m]|m([^p]|p([^l]|l[^e])))))'
other_suffix+='|s([^a]|a([^m]|m([^p]|p([^l]|l[^e]))))'
other_suffix+='|t([^e]|e([^m]|m([^p]|p([^l]|l([^a]|a([^t]|t[^e])))))))'

guard_patterns=(
  "${guard_name_start}[.]ssh${name_end}"
  "${guard_name_start}[.]aws${name_end}"
  "${guard_name_start}[.]kube${name_end}"
  "${guard_name_start}kubeconfig${name_end}"
  "${guard_name_start}[.]config/gcloud${name_end}"
  "${guard_name_start}[.]config/(1password|op|keeper|ksm|ghtkn)${name_end}"
  "${guard_name_start}[.](1password|keeper|ghtkn)${name_end}"
  "${guard_name_start}[.]local/share/(ghtkn|atuin)${name_end}"
  "${guard_name_start}[.]atuin${name_end}"
  "${guard_name_start}[.]claude/[.]credentials[.]json"
  "${guard_name_start}[.]codex/auth[.]json"
  "${guard_name_start}[.]env${name_end}"
  "${guard_name_start}[.]env[.]${other_suffix}"
)

guard_watch_unresolvable \
  "${guard_name_start}(ssh|aws|kube|atuin|ghtkn|keeper|1password|gcloud|credentials|[.]env)"

guard_advice='These paths hold credentials, cluster access, or shell history that must not reach an agent transcript. Take the value from its vault at run time instead: op run, ksm exec, or ghtkn exec.'

guard_main
