# Privacy Policy — crossroads swift

**Status:** DRAFT — pending legal review
**Last updated:** 2026-04-17
**Controller:** Neurogrid SAS, France (SIREN: TBD)
**Contact:** privacy@neurogrid.me _(confirm address)_

---

## 1. What we collect

- **Account data** — email, name, password hash, account preferences
- **Usage data** — feature interactions, timestamps, IP (truncated), user-agent
- **Content you provide** — _(list the data types crossroads swift takes in)_
- **Billing data** — via Stripe (we don't store card numbers)

## 2. Why we collect it

- To operate crossroads swift (contract)
- To improve the product (legitimate interest — aggregated / anonymized)
- To bill you (contract + legal)
- To respond to support (contract)

## 3. Subprocessors

_(list actual subprocessors used by crossroads swift — template includes the common set)_

| Subprocessor | Role | Region | DPA in place |
|--------------|------|--------|--------------|
| Vercel (or chosen host) | hosting | EU / US | TBD |
| Supabase | database + auth + storage | EU | TBD |
| Anthropic | AI inference | US (EU routing where available) | TBD |
| OpenAI | AI inference | US | TBD |
| Stripe | payments | EU / US | TBD |
| Google Workspace | support email | EU / US | TBD |

## 4. Data residency

EU-first. Primary storage in EU regions. Specific routing per table in `retention-policy.md`.

## 5. Retention

See `retention-policy.md` for per-entity schedules. Summary: accounts kept until deletion; usage logs 90 days; analytics 12 months; invoices 10 years (legal).

## 6. Your rights (GDPR)

You can ask to:

- Access your data (subject-access request) — fulfilled within 15 days (target), 30 days (max)
- Correct your data
- Delete your account (soft-delete → 30 days → purge)
- Port your data (machine-readable export)
- Object to processing for legitimate-interest grounds
- Complain to the French CNIL

Reach: `privacy@neurogrid.me` _(confirm)_

## 7. AI features

See `ai-act-transparency.md` for the full list of generative features. All AI-generated outputs are labeled. We do not use your inputs to train third-party models beyond inference.

## 8. Contact

Neurogrid SAS — _(address TBD)_ — `privacy@neurogrid.me`

## 9. Changes

Material changes are announced in-product 30 days before taking effect. Changelog is maintained in `audit-log.md`.

---

## TODOs before publishing

- [ ] Fill SIREN + registered address
- [ ] Confirm contact email
- [ ] Confirm each subprocessor's DPA status
- [ ] Legal review
- [ ] French-language version
