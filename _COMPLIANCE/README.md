# _COMPLIANCE — crossroads swift

Legal + regulatory artifacts for crossroads swift. Everything here is **DRAFT** until reviewed by legal counsel — the public-facing versions should be marked as such on the site.

## Contents

- `privacy-policy.md` — GDPR-aligned privacy policy (public)
- `terms.md` — Terms of Service (public)
- `dpa.md` — Data Processing Agreement template (per customer when B2B)
- `ai-act-transparency.md` — EU AI Act Art. 50 disclosures (generative features)
- `retention-policy.md` — per-entity retention schedule (internal + public summary)
- `audit-log.md` — append-only log of data/infra changes

## Review cadence

- **Quarterly** — sweep all docs, update "Last reviewed" dates
- **On schema change** — update `retention-policy.md` before the migration lands
- **On new AI feature** — update `ai-act-transparency.md` before release
- **On new subprocessor** — update `privacy-policy.md` + log in `audit-log.md`
- **On data incident** — cross-link incident report in `audit-log.md`

## Triggers checklist

- [ ] New feature touching personal data → privacy-policy + retention-policy
- [ ] New subprocessor (AI provider, analytics, CDN) → privacy-policy + audit-log
- [ ] New AI-generated output visible to users → ai-act-transparency
- [ ] B2B customer requests a DPA → fill `dpa.md` template per customer
- [ ] Data subject access / deletion request received → audit-log + process in 30 days

## Owner

Birahim is the controller. Legal counsel (TBD) reviews major revisions. Quarterly review is Birahim's responsibility.
