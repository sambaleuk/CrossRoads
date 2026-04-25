# _OPS — crossroads swift

How to keep this product alive. Everything in this folder is operational — on-call, deploys, dashboards, cost caps.

## Contents

- `runbooks/` — product-specific runbooks (and links to generic ones in `07_INFRA/runbooks/`)
- `dashboards.md` — where to look when you want to know if the system is healthy
- `oncall.md` — response windows, solo-founder posture, critical-issue definition
- `cost.md` — monthly spend, caps, review cadence
- `deploy.md` — pre-deploy checklist, deploy flow, rollback procedure

## Rule of thumb

- Generic issue (Vercel down, Supabase down, API outage) → use the runbook in `/07_INFRA/runbooks/`
- Product-specific (an `crossroads swift` workflow broke, a cron failed) → product runbook here
- Something broke → write a postmortem in `_INCIDENTS/YYYY-MM-DD-slug.md` (append-only)
