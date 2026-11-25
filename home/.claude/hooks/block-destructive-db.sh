# The destructive-database guard of docs/adr/0007-agent-guardrails.md.
# lib/guard.sh runs it and holds the deny-only contract.

guard_subject='The destructive-database guard'

# Lowercase ERE, matched against a quote-stripped and newline-flattened copy of
# the command, so that token concatenation cannot hide an operation. A runner-to
# -task span may cross a control operator: a pause for review costs less than a
# shell parser. \b is in neither bash nor POSIX ERE, so a name ends with
# ([^[:alnum:]_]|$). `truncate` on its own also matches coreutils' truncate and
# the word in any argument; the over-match is the cheaper side of the trade.
guard_patterns=(
  'prisma[[:space:]]+.*migrate[[:space:]]+reset([^[:alnum:]_]|$)'
  'prisma[[:space:]]+.*db[[:space:]]+push[[:space:]]+.*--force-reset([^[:alnum:]_]|$)'
  'drizzle-kit[[:space:]]+.*push([[:space:]]|$).*--force([^[:alnum:]_]|$)'
  '(rails|rake)[[:space:]]+.*db:(setup|schema:load)([^[:alnum:]_]|$)'
  'manage\.py[[:space:]]+.*(flush|reset_db|sqlflush)([^[:alnum:]_]|$)'
  'sequelize[[:space:]]+.*db:drop([^[:alnum:]_]|$)'
  'sequelize[[:space:]]+.*db:migrate:undo:all([^[:alnum:]_]|$)'
  'typeorm[[:space:]]+.*schema:drop([^[:alnum:]_]|$)'
  'knex[[:space:]]+.*migrate:rollback[[:space:]]+.*--all([^[:alnum:]_]|$)'
  'db:(reset|drop|nuke|wipe|clear)([^[:alnum:]_]|$)'
  '(^|[^[:alnum:]_])dropdb([^[:alnum:]_]|$)'
  'mysqladmin[[:space:]]+(.*[[:space:]])?drop([^[:alnum:]_]|$)'
  'drop[[:space:]]+(database|schema|table)([^[:alnum:]_]|$)'
  'truncate([[:space:]]+table)?([^[:alnum:]_]|$)'
)

# A SQL comment or a shell construct between the keywords (DROP/**/DATABASE)
# defeats the patterns above, and resolving one needs a shell. Only the verbs
# are listed: `table` or `database` on its own appears in ordinary commands.
guard_watch_unresolvable "${guard_name_start}(drop|truncate|dropdb|db:)"

guard_advice='These operations wipe data unconditionally, and a test-environment marker does not prove which datasource the client reaches. A transient schema error is environment noise, not a reason to reset: report the failing command instead.'

guard_main
