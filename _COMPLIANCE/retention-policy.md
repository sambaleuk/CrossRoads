# Retention policy — crossroads swift

**Status:** DRAFT — confirm each row with the actual DB schema + legal
**Last reviewed:** 2026-04-17
**Review cadence:** quarterly + on any schema change

---

## Per-entity schedule (template — customize for crossroads swift)

| Entity / table | What it holds | Retention | Deletion trigger | Storage location | Legal basis |
|----------------|---------------|-----------|------------------|------------------|-------------|
| `users` | email, name, hashed pw | until account deletion → 30d soft-delete → purge | user delete; 3y inactivity → email then purge | EU | contract |
| (product-specific table) | (fill) | (fill) | (fill) | (fill) | (fill) |
| `generations_log` | AI call history, prompts (if crossroads swift uses AI) | 90 days | 90-day rolling cron | EU | legitimate interest |
| `events` / analytics | usage events | 12 months | 12-month rolling cron | EU | legitimate interest |
| `invoices` | billing records | 10 years | n/a | Stripe + backup | legal (accounting) |
| `audit_log` | data/infra changes | 2 years | 2-year rolling cron | EU | legitimate interest + GDPR accountability |
| `backups` | encrypted snapshots | 30 days | 30-day rolling | primary + offsite | operational |

## Cron jobs that implement this

_(fill with actual job names + schedule + location)_

- `purge_deleted_users` — daily
- `rotate_<entity>` — weekly / monthly
- `rotate_audit_log` — monthly (archive older than 2 years)

**Location of cron definitions:** _(fill — `_CODE/scripts/cron/` or n8n workflows)_

## Verification checklist (quarterly)

- [ ] Pull row counts per table and check for retention drift
- [ ] Spot-check: find the oldest row in each table, verify it's within the retention window
- [ ] Confirm all retention cron jobs ran in the last 30 days
- [ ] Update "Last reviewed" at top of this doc

## When a schema change needs a retention-policy update

- New table → add a row here before the migration lands
- Column added that holds PII → re-evaluate retention for the table
- New region / subprocessor → update `privacy-policy.md` + this doc

## User-initiated deletion

- From settings → "Delete account" → soft-delete with date of purge shown
- Export requested → generated within 30 days, emailed as a zip
- Granular deletion (delete one item) → available in UI where relevant

## Subject-access request turnaround

Target: 15 days (commitment), max 30 days (GDPR).
