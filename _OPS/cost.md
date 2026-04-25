# Cost — crossroads swift

Monthly spend breakdown + caps.

## Current spend (template — fill monthly)

| Item | Provider | Plan | Monthly | Notes |
|------|----------|------|---------|-------|
| Hosting | (fill) | (fill) | € — | — |
| Database | (fill) | (fill) | € — | — |
| AI (Anthropic) | Anthropic | usage | € — | soft cap below |
| AI (OpenAI) | OpenAI | usage | € — | soft cap below |
| Automations | (fill — n8n VPS) | (fill) | € — | — |
| Domain / DNS | (fill) | — | € — | — |
| Misc | — | — | € — | — |
| **Total** | | | **€ —** | |

## Caps

| Item | Soft cap | Hard cap | Action at hard cap |
|------|----------|----------|--------------------|
| AI total / month | 50 € | 150 € | features using paid AI: OFF |
| External APIs | — | — | — |

## Review cadence

- Monthly: pull actuals into the table above + compare to soft cap
- Quarterly: check plan tiers still make sense

## Rule

Any line item that jumps 2× month-over-month without a reason in `CHANGELOG.md` is an incident — file in `_INCIDENTS/`. Runaway AI cost is the most common cause.
