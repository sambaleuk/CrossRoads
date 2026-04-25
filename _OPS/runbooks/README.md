# Runbooks — crossroads swift

Product-specific runbooks live in this folder. Generic ones live in `/07_INFRA/runbooks/` — we link instead of duplicate.

## Product-specific

_(none yet — add files named `<symptom-slug>.md`)_

## Generic (lookup from `/07_INFRA/runbooks/`)

Relative path: `../../../../07_INFRA/runbooks/`

Common ones to reference:

- `vercel-outage.md` — hosting down / deploy failing
- `supabase-down.md` — Postgres / auth / storage issues
- `vps-down.md` — n8n / Dokploy / other self-hosted
- `dns-issue.md` — domain not resolving
- `ssl-cert-expired.md` — HTTPS broken
- `anthropic-api-outage.md` — Claude API failing
- `openai-api-outage.md` — OpenAI API failing
- `stripe-outage.md` — billing / webhooks failing
- `db-restore-from-backup.md` — data loss recovery
- `secret-leaked.md` — rotate + audit
- `migration-rollback.md` — reverse a Prisma migration

See `/07_INFRA/runbooks/INDEX.md` for the full list.

## Rule

If you add a product runbook here, it should be the minimum delta on top of the generic one — not a duplicate.
