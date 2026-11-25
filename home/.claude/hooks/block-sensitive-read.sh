# The credential-read guard of docs/adr/0007-agent-guardrails.md, under a name
# that AGENTS.md allows a tracked file to carry. lib/guard.sh runs it and holds
# the deny-only contract.

guard_subject='The sensitive-read guard'

# A path counts when it is rooted at the home directory, however a shell spells
# that, or when it leads a command argument. This repository's own tracked
# copies (home/.ssh/config, home/.config/ghtkn/) sit behind a relative segment
# and stay readable. The scan is lowercase, with quotes already removed.
hook_home='(^|[^[:alnum:]_.~/-])(~/|[$][{]?home[}]?/|/users/[^/[:space:]]+/|/home/[^/[:space:]]+/)?'
hook_end='([^[:alnum:]_.-]|$)'

guard_patterns=(
  "${hook_home}[.]ssh${hook_end}"
  "${hook_home}[.]aws${hook_end}"
  "${hook_home}[.]kube${hook_end}"
  "${hook_home}[.]config/gcloud${hook_end}"
  "${hook_home}[.]config/(1password|op|keeper|ksm|ghtkn)${hook_end}"
  "${hook_home}[.](1password|keeper|ghtkn)${hook_end}"
  "${hook_home}[.]local/share/(ghtkn|atuin)${hook_end}"
  "${hook_home}[.]atuin${hook_end}"
  "${hook_home}[.]claude/[.]credentials[.]json"
  "${hook_home}[.]codex/auth[.]json"
  # .env and its per-environment variants, but not the committed templates
  # (.env.example, .env.sample) and not direnv's .envrc.
  "(^|[^[:alnum:]_.-])[.]env${hook_end}"
  "(^|[^[:alnum:]_.-])[.]env[.](local|development|dev|staging|stg|production|prod|test)${hook_end}"
)

guard_advice='These paths hold credentials, cluster access, or shell history that must not reach an agent transcript. Take the value from its vault at run time instead: op run, ksm exec, or ghtkn exec.'

guard_main
