# The destructive-database guard of docs/adr/0007-agent-guardrails.md.
# lib/guard.sh runs it and holds the tier contract.

guard_subject='The destructive-database guard'

guard_ask_why='a database client or a SQL verb next to a shell expansion, a comment, or a double-dash option, so the statement that reaches the database may be assembled or hidden where no matcher can read it'

guard_advice='These operations wipe data unconditionally, and a test-environment marker does not prove which datasource the client reaches. A transient schema error is environment noise, not a reason to reset: report the failing command instead.'

# Lowercase ERE, matched against a quote-stripped and newline-flattened copy of
# the command, so that token concatenation cannot hide an operation. A runner-to
# -task span may cross a control operator: a pause for review costs less than a
# shell parser. \b is in neither bash nor POSIX ERE, so a name ends with
# ([^[:alnum:]_]|$). `truncate` on its own also matches coreutils' truncate and
# the word in any argument; the over-match is the cheaper side of the trade.
name_end='([^[:alnum:]_]|$)'

# What may stand between two SQL keywords: whitespace, a block comment, or a
# line comment, which the normalizer has already turned into one line.
gap='([[:space:]]|/\*[^*]*\*/|--[^[:space:]]*[[:space:]])+'

# A tool may be written with a version (`npx prisma@6 ...`), and a package may
# ship more than one binary for one tool (`sequelize-cli`, `typeorm-ts-node-esm`).
version='(@[^[:space:]]*)?'

# Exact rules: a literal command, written as the tool spells it.
guard_rule prisma-migrate-reset deny "prisma${version}[[:space:]].*migrate[[:space:]]+reset${name_end}"
guard_rule prisma-push-force-reset deny "prisma${version}[[:space:]].*db[[:space:]]+push[[:space:]].*--force-reset${name_end}"
guard_rule drizzle-push-force deny "drizzle-kit${version}[[:space:]].*push[[:space:]].*--force${name_end}"
guard_rule rails-db-setup deny "(rails|rake)[[:space:]].*db:(setup|schema:load)${name_end}"
guard_rule django-flush deny "manage\\.py[[:space:]].*(flush|reset_db)${name_end}"
guard_rule sequelize-undo-all deny "sequelize(-cli)?${version}[[:space:]].*db:migrate:undo:all${name_end}"
guard_rule typeorm-schema-drop deny "typeorm(-ts-node-(commonjs|esm))?${version}[[:space:]].*schema:drop${name_end}"
guard_rule knex-rollback-all deny "knex${version}[[:space:]].*migrate:rollback[[:space:]].*--all${name_end}"
guard_rule script-db-wipe deny "db:(reset|drop|nuke|wipe|clear)${name_end}"
guard_rule dropdb deny "(^|[^[:alnum:]_])dropdb${name_end}"
guard_rule mysqladmin-drop deny "mysqladmin[[:space:]](.*[[:space:]])?drop${name_end}"
guard_rule drop-database deny "drop${gap}database${name_end}"
guard_rule drop-schema deny "drop${gap}schema${name_end}"
guard_rule drop-table deny "drop${gap}table${name_end}"
guard_rule truncate deny "truncate${name_end}"

# Shape rules. The verb need not survive for the command to reach a database:
# `drop` next to any expansion (`echo {DROP,DATABASE} x | psql`) cannot be
# read, and the whole statement can arrive in a variable (`psql -c "$SQL"`) or
# hide behind a comment (`--`, or MySQL's `#`, which the flattened newline
# leaves running to the end of the command). `table` or `database` on its own
# appears in ordinary commands, so only the verb is watched. The cost is that an
# ordinary `select *` and any `--flag` on a client are asked about too;
# measured in docs/verification.md.
client='(psql|mysql|mariadb|sqlite3|prisma|drizzle-kit|pg_restore|db:)'
client_construct='([$`*?[{#]|--)'
# The verb may follow the expansion directly (`{drop,database}`), where the one
# character cannot be both the expansion and the character before the verb.
guard_rule drop-expansion ask "${guard_name_start}drop.*${guard_expansion}"
guard_rule drop-expansion-reversed ask "${guard_expansion}(.*[^[:alnum:]_-])?drop"
guard_rule_both_orders client-construct ask "${guard_name_start}${client}" "$client_construct"
# A brace list can open on the client (`pnpm run {db:res,x}et`), where the one
# character cannot be both the construct and the character before the client.
guard_rule client-after-brace ask "[{]${client}"
