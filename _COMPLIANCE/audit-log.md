# Audit log — crossroads swift

Append-only log of changes that affect data, access, or infra. Required for GDPR accountability + internal governance.

**Rule:** one line per event, in chronological order. Never edit past entries. Corrections go as new "CORRECTION:" lines.

Each line format:

```
YYYY-MM-DD HH:MM | <actor> | <category> | <action> | <reason / link>
```

Categories: `schema`, `access`, `secret`, `subprocessor`, `data-export`, `data-delete`, `policy`, `incident`.

---

## Entries

```
2026-04-17 00:00 | birahim | policy | compliance folder scaffolded with draft policies | initial setup
```

_(append new entries below this line)_

---

## When to log

- [ ] Someone new gets access to production data
- [ ] A schema migration lands on production DB
- [ ] A secret is rotated
- [ ] A subprocessor is added, removed, or their region changes
- [ ] A data export is produced for a user (subject-access request)
- [ ] A user account is hard-deleted (beyond the normal soft-delete flow)
- [ ] A privacy policy / ToS revision is published
- [ ] An incident is declared (cross-link to `_INCIDENTS/`)

## What NOT to log here

- Normal user actions (those live in `events` table, not here)
- Developer commits (git is the audit log for code)
- Routine cron runs (except failures, which become incidents)

## Retention

Keep forever (this file is tiny and the compounding value is high). If it ever exceeds ~500 lines, split by year: `audit-log-2026.md`, `audit-log-2027.md`.
