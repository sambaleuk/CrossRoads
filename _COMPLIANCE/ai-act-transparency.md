# AI Act Transparency — crossroads swift

**Status:** DRAFT — pending legal review
**Regulatory basis:** EU AI Act — in particular Art. 50 (transparency for limited-risk generative systems) and Annex III (high-risk categories check).
**Last updated:** 2026-04-17

---

## Our classification

crossroads swift is currently classified as **limited-risk** under the AI Act (see the Annex III check below). If that changes — we revisit this doc before the feature ships.

## AI features inventory

| Feature | Provider | Model (example) | UI label shown to user | Public disclosure |
|---------|----------|-----------------|------------------------|-------------------|
| _(list each AI feature in crossroads swift)_ | — | — | — | — |

> Rule: every generative output is labeled with "AI-generated" or equivalent at the point of display. Reuse downstream by users must keep the label — this is covered in `terms.md`.

## Obligations we commit to

- **Transparency (Art. 50):** end users are told they are interacting with AI or receiving AI-generated content.
- **Labeling:** generative outputs carry a visible machine-readable and human-readable marker.
- **Provenance:** we keep, at minimum, the model name + provider + timestamp per generation in `generations_log` — see `retention-policy.md`.
- **No deceptive deepfakes:** we do not generate content impersonating real identifiable individuals without their consent.

## Triggers for updating this doc

- [ ] New generative feature shipped → add row to inventory, confirm UI label, update public disclosure before release
- [ ] Model swap (e.g., Claude 3.5 → Claude 4) → update column, no user-facing change unless behavior shifts
- [ ] New AI provider → update `privacy-policy.md` subprocessor list + `audit-log.md`
- [ ] A feature starts matching an Annex III high-risk category → STOP, assess, legal review before shipping

## Annex III high-risk check

None of crossroads swift's current features fall into Annex III:

- ❌ Biometric identification / categorization
- ❌ Critical infrastructure management
- ❌ Education or vocational-training access decisions
- ❌ Employment / worker-management decisions
- ❌ Essential private / public services access (credit scoring, public benefits)
- ❌ Law-enforcement use
- ❌ Migration / asylum / border control
- ❌ Administration of justice / democratic processes

_(revisit this list every quarter + on every new feature)_

## Prohibited-use check (Art. 5)

We don't do subliminal manipulation, social scoring, real-time biometric identification in public spaces, or any other Art. 5 prohibited practice.

## Evidence file

For each major AI feature, we keep a short dated note in `_RESEARCH/ai-act-evidence/<feature>.md` with: provider + model, eval results (bias / hallucination spot-checks), data-input audit. This is our accountability paper trail.

---

## TODOs

- [ ] Fill the inventory table with the real features of crossroads swift
- [ ] Confirm UI labels are in place across all surfaces
- [ ] Legal review
