# Deploy — crossroads swift

## Pre-deploy checklist

- [ ] CI green on main
- [ ] CHANGELOG.md updated (new line under `[Unreleased]` or new version bumped)
- [ ] Migration (if any) has a rollback path
- [ ] Env vars (if new) added to `.env.example` AND provisioned in production
- [ ] Feature flags for anything partially-shipped: default OFF
- [ ] Tested on staging or a preview URL (if the product has one)

## Deploy flow

1. Merge to `main` (branch model: trunk-based, main = deployed)
2. Hosting auto-deploys on push (confirm: which provider / which branch)
3. Watch deploy log; first traffic smoke-test within 5 min
4. Note the deployed SHA in `CHANGELOG.md` if it wasn't already

## Rollback

1. Revert the commit on `main` → push → auto-redeploy
2. OR redeploy the previous good SHA from the hosting console
3. If DB migration was involved → follow the migration rollback step recorded at deploy time
4. File an `_INCIDENTS/` postmortem if rollback took > 15 min or caused user-visible breakage

## Never

- Deploy Friday after 16:00 local
- Deploy < 48 h before a vacation
- Deploy without bumping CHANGELOG.md
- Run a migration without a rollback path
- Skip the checklist because "it's small"

## Hotfix flow

For SEV-1 (site down / payment broken / data loss):

1. Write the one-line incident entry in `_INCIDENTS/` first (backfill details later)
2. Patch on `main` → deploy (skip the full checklist, keep CHANGELOG)
3. Postmortem within 24 h
