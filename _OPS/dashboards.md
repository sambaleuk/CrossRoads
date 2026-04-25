# Dashboards — crossroads swift

Pointers to live dashboards. This file holds URLs + "what healthy looks like", never values (values get stale in 24h).

## Health

| Metric | Source | Healthy | Alert threshold |
|--------|--------|---------|-----------------|
| Uptime | (fill) | ≥ 99.5% / 30d | < 99% / 30d |
| Error rate | (fill) | < 1% | > 2% |
| p95 latency | (fill) | < 1s | > 3s |
| DB CPU | (fill) | < 40% | > 70% sustained |
| AI / external API spend | provider console | on plan | > 2× 30d avg |

## Business

| Metric | Source | Cadence |
|--------|--------|---------|
| (fill) | (fill) | weekly |

## Bookmarks

- Hosting: (fill — Vercel / VPS / Dokploy)
- DB / Supabase: (fill — project id)
- Analytics: (fill — Plausible / PostHog / etc.)
- Automations: (fill — n8n workflows / cron)
- AI providers: (fill — Anthropic / OpenAI console)

## Rule

If a dashboard link is broken or a metric is missing — that's an incident-in-waiting. File in `_INCIDENTS/` or add to `_ROADMAP/backlog.md`.
