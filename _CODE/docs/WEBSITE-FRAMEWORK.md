# XRoads — Website Framework

> Structural skeleton for the XRoads landing site.
> Intended as input for a copy agent. Contains no final copy.
> Each section states its purpose, hierarchy, content blocks, visual treatment, and CTA logic.

---

## 0. Strategic prerequisites the copy agent needs from Bigouz

Before writing copy, the copy agent should be told:

- **Vision pick.** Vision A (dev tool) or Vision B (métier orchestrator). The framework below is vision-agnostic in structure, but the substance of every section flips depending on the pick. See section 11 for the variant notes.
- **Primary ICP.** One persona, named in human terms (e.g. "Solo Mac dev shipping side-projects" or "Solo founder launching a SaaS without a team"). All copy is written to this person, not to the market.
- **One headline outcome.** A single sentence the visitor must believe by the end of the hero. Not a feature claim, an outcome claim.
- **Tone constraint.** No em dashes anywhere. No emojis. No engineering vanity ("52 actors", "66k LOC", "21 GRDB tables") in customer-facing copy. Birahim-voice is overridden by default.

---

## 1. Site shape

Single-page landing, plus three out-bound destinations: GitHub, Docs, Download.

```
[Top nav] -- Logo • Product • Docs • GitHub • Download
[Hero]
[Social proof strip]
[How it works]
[Differentiators]
[Live proof / demo]
[Under the hood]
[Privacy & local-first]
[Pricing / OSS statement]
[FAQ]
[Final CTA]
[Footer]
```

Mobile: same vertical sequence, nav collapses to a sheet, video loops auto-pause out of view.

---

## 2. Top navigation

**Purpose:** Reduce the cost of conversion to one click, in any state of the visitor's curiosity.

**Hierarchy:** Logo (left). Five links (right): Product, Docs, GitHub (with star count), Download (primary button).

**Content blocks:** Logo lockup. Five text links. One pill button (Download / Get Started / Try It).

**Visual treatment:** Sticky on scroll, subtle transparency to dark background as the user moves past the hero. Star count is live-pulled from GitHub.

**CTA:** Primary CTA in the nav matches the primary CTA in the hero. Never two competing CTAs.

---

## 3. Hero

**Purpose:** In one screen, the visitor must understand (a) what XRoads does, (b) for whom, (c) why it is different, (d) what to do next. If the hero fails, the rest of the page does not save the conversion.

**Hierarchy:**
- H1 — outcome promise (one short sentence)
- H2 — qualifier (one sentence, names the audience)
- Body — three short lines or one paragraph (the wedge)
- Primary CTA — Download / Get Started
- Secondary CTA — See it run / Watch a 60s demo
- Visual right side — a working artifact (looped screen recording of agents shipping in parallel, OR a single dense screenshot of the dashboard)

**Content blocks:**
- Brand mark + product name
- H1 (max 8 words)
- Subhead (max 18 words)
- Optional bullet trio (max 5 words each)
- Two CTAs (primary, secondary)
- Hero artifact (video or screenshot)
- Tiny line under CTAs: platform support + license (e.g. macOS 14+, Apache 2.0)

**Visual treatment:** Dark mode by default to match the app's likely aesthetic. The artifact carries the visual weight, the text does not. The artifact must be a real frame from the product, never a stylized illustration.

**Copy-agent notes:**
- The H1 cannot be a feature ("Run six AI agents in parallel"). It must be an outcome ("Ship a week of features in a night" or "Launch the campaign while you sleep").
- The subhead names the ICP without saying "for developers" generically. Be specific.
- One CTA must lead to action (download / install). The other must lead to belief (demo / video).

---

## 4. Social proof strip

**Purpose:** In the second screen, the visitor must believe other people use this. Conversion math says belief precedes evaluation.

**Hierarchy:** Single horizontal strip, low visual weight.

**Content blocks (pick three of the four, depending on what is true):**
- GitHub star count + "Open source under Apache 2.0"
- A logo row (companies, agencies, or studios who use it). If none yet: skip this row, do not fake it.
- A user quote (one line, one named person, role). If none yet: replace with a maker quote from Bigouz or Birahim.
- A counter ("X agent runs completed", "Y stories shipped", live or static). If unsourced: skip, never invent.

**Visual treatment:** Single line of small monochrome marks on a contrasting strip. No celebrity treatment. Confidence comes from quietness here, not loudness.

**Copy-agent notes:** If the product has no real social proof yet, this section is replaced by a single line of maker credibility (who built it, why) — but it must remain in the same screen position, not pushed down.

---

## 5. How it works

**Purpose:** The visitor must understand the mechanism in 15 seconds. This section defeats skepticism by making the magic legible.

**Hierarchy:**
- H2 — section header (one short line)
- Sub-line — one sentence framing the steps
- Three or four step blocks, horizontal on desktop, vertical on mobile
- Each step: number, icon or glyph, one-line title, one-sentence description

**Content blocks:**
- Step 1 — input (what the user gives the system)
- Step 2 — orchestration (what the system does)
- Step 3 — execution (what comes out)
- Step 4 (optional) — review / merge / ship

**Visual treatment:** A flow diagram, not isolated cards. Connecting lines or arrows between the steps to make the pipeline literal. A single muted accent color on the active path. Avoid robot icons, brain icons, sparkle icons.

**Copy-agent notes:**
- Each step verb should be a real verb the product does, not a marketing verb. ("Routes", "Runs", "Merges" — not "Empowers", "Transforms", "Unlocks".)
- The diagram is the hero of this section. Copy is caption-weight.

---

## 6. Differentiators (the wedge)

**Purpose:** The visitor knows what XRoads does. Now they need to know why XRoads, not Devin / Cursor / Claude Code / Aider / Lovable / Replit Agent. This section is the competitive moat made visible.

**Hierarchy:**
- H2 — section header
- Three or four cards, equal weight, grid layout

**Content blocks per card:**
- One-glyph visual mark (consistent set across all cards, no mixed icon styles)
- Card title (max 4 words)
- Card body (max 25 words)
- Optional micro-link ("Read more", goes to a docs page or a deeper section)

**Differentiator slots (Vision A — dev tool):**
1. Parallel agents on real worktrees, not a queue
2. Local ML, zero cloud telemetry
3. Conflict prediction before merge
4. Native macOS, no browser tab

**Differentiator slots (Vision B — métier orchestrator):**
1. Full pipelines, not single-prompt outputs
2. Métier playbooks, not generic agents
3. Local + private by default
4. Native app, not a browser tool

**Visual treatment:** Cards on a quiet background. Equal sizing. No "popular" badges or hierarchy among the cards. The visual mark is small and monochrome. Uniformity is the point.

**Copy-agent notes:**
- Every card body must contain an implicit competitor comparison without naming names ("not a queue" vs Cursor agent mode, "zero cloud telemetry" vs Devin, "full pipelines" vs Lovable single-prompt, etc.).
- Cards do not stand alone. Read top to bottom they must compose a coherent thesis.

---

## 7. Live proof / demo

**Purpose:** Belief is earned by showing the product running. Reading is no longer enough at this point in the page.

**Hierarchy:**
- H2 — section header (one short line)
- Body lead-in (one sentence)
- Visual block — the demo
- Caption under the visual (one sentence)
- Tertiary CTA — "Watch full demo" or "See agents working live"

**Visual treatment options (pick one):**
- Looped video, 30-60s, of the dashboard with agents shipping in parallel
- Live tail of a real run (animated terminal, scripted but real frames)
- Side-by-side: PRD on the left, code committed on the right, time-collapsed

**Copy-agent notes:**
- This section's copy is minimal. The visual carries the proof.
- The caption should name the time saved, not the technology used.

---

## 8. Under the hood (credibility, brief)

**Purpose:** For the technically curious visitor, prove the product is not vaporware. For the non-technical visitor, this section is skippable and the page must remain intelligible without it.

**Hierarchy:**
- H2 — section header
- Three or four data points, horizontal, low visual weight
- Each data point: a small label and a number or fact

**Content blocks:**
- Native: macOS 14+ (Apple Silicon)
- Open source: Apache 2.0
- Local ML: 3 models, trained on your machine
- Cross-platform: Tauri sibling for Windows / Linux

**Visual treatment:** Sober, near-monospaced typography. No bar charts, no progress rings, no marketing infographics. This section is read by skeptics; it must look like a spec sheet, not a brochure.

**Copy-agent notes:**
- This is the only section where engineering precision is permitted, and even here it is restrained. No "52 actors", no "66k LOC". Those numbers do not sell, they confess.
- If a data point cannot be sourced precisely, drop it.

---

## 9. Privacy & local-first

**Purpose:** A standalone section because in 2026, privacy is a wedge, not a footnote. Devin and Cursor are cloud. XRoads is not. This is one of the strongest reasons a Mac developer or a privacy-aware founder picks XRoads.

**Hierarchy:**
- H2 — section header
- One-sentence claim
- Three short statements (what does not happen):
  - No code leaves your machine
  - No telemetry on your runs
  - No cloud account required
- Tertiary link — privacy policy / architecture page

**Visual treatment:** Quiet section. A single small visual mark (a closed lock, a local-only network glyph, abstract). Background slightly differentiated from adjacent sections.

**Copy-agent notes:**
- The three statements are negative-form on purpose ("no X", "no Y", "no Z"). Negative voice conveys discipline more credibly than positive voice here.
- Avoid "privacy-first", "secure by design", "enterprise-grade". These phrases are filler.

---

## 10. Pricing / open source statement

**Purpose:** Resolve the visitor's unspoken question ("how much does this cost") before they have to ask it.

**Hierarchy depends on the model:**

**Variant A — Pure OSS, no paid tier yet:**
- H2 — header
- One paragraph: "XRoads is Apache 2.0. Free to download, modify, and deploy."
- One CTA — Download
- One link — Star us on GitHub

**Variant B — OSS plus a paid tier (cloud, hosted, support):**
- H2 — header
- Two columns or two cards: Free / Pro
- Each card: name, price, three-line feature summary, CTA
- Below: a one-line "open source forever" reassurance

**Variant C — OSS only with sponsorship CTA:**
- H2 — header
- One paragraph
- Sponsorship link (GitHub Sponsors, OpenCollective)

**Visual treatment:** No fake "limited time" timers. No "save 30%" decals. Sober, calm, credible.

**Copy-agent notes:**
- Bigouz must tell the copy agent which variant (A / B / C) is true today. Do not assume.

---

## 11. FAQ

**Purpose:** Pre-empt the questions that block conversion. A well-built FAQ closes the loop on every doubt the page raised but did not directly answer.

**Hierarchy:**
- H2 — section header
- 6-8 questions, accordion-collapsed by default, expand on click
- Each question: a literal question, a 2-3 sentence answer

**Question slots (must-haves):**
- "Does this require an API key?" (Yes — Anthropic / OpenAI / Google)
- "Does my code leave my machine?" (No, except via the agent's own API call to its model provider)
- "What happens if an agent breaks something?" (Worktree isolation, manual review of every PR)
- "Windows or Linux support?" (Tauri sibling repo)
- "How is this different from Devin / Cursor / Aider?" (Three-line comparison; do not start with "Unlike")
- "Is it really free?" (Apache 2.0, link to the license)
- "What models does it support?" (Claude, Gemini, Codex, names of CLIs)
- "How do I report a bug?" (GitHub issues link)

**Visual treatment:** Lightweight, monospaced labels for the question, regular for the answer. Active question is highlighted with a small bar on the left, not a colored background.

**Copy-agent notes:**
- Answer the literal question first. Do not redirect to a feature pitch.
- Avoid "Great question". Avoid "We're glad you asked".

---

## 12. Final CTA

**Purpose:** Last conversion point. The visitor is at the bottom of the page; they have either decided or they have not. The CTA must close cleanly.

**Hierarchy:**
- One-sentence H2 (an imperative)
- Two buttons (Primary: Download / Get Started; Secondary: Star on GitHub)
- One micro-line under (the same platform + license info as in the hero)

**Visual treatment:** A full-width band, contrasting background, large but quiet. No background gradients with five colors. One accent color, used confidently.

**Copy-agent notes:**
- Reuse the same H1 outcome promise from the hero, but in imperative form. Repetition is intentional. The visitor has been led to this exact decision.

---

## 13. Footer

**Purpose:** Functional. Discoverability of secondary surfaces.

**Content blocks:**
- Column 1 — Product (Download, Docs, Changelog, Roadmap)
- Column 2 — Project (GitHub, Issues, Contributing, License)
- Column 3 — Neurogrid (Studio link, Other products, Contact)
- Column 4 — Legal (Privacy, Terms, Acknowledgements)
- Bottom strip — Copyright, "Built by Neurogrid", small social marks

**Visual treatment:** Minimal. Light text on dark, small type, generous padding, no widget cluster.

---

## 14. Vision-variant notes for the copy agent

This framework is structurally identical for both visions. The substance flips per section.

**If Vision A (dev tool):**
- ICP language is engineer-tribal but not vain. ("You ship features. We run six of you in parallel.")
- Differentiators 6.1 - 6.4 use the dev-tool slots.
- FAQ leans on agent / branch / merge concerns.
- Demo is a real coding run, with a real repo.

**If Vision B (métier orchestrator):**
- ICP language is founder / marketer / agency tribal.
- Differentiators 6.1 - 6.4 use the métier-orchestrator slots.
- FAQ leans on output type, business pipeline, deliverable concerns.
- Demo is a marketing campaign launch or e-commerce product launch, end-to-end.
- The "Under the hood" section drops the open-source / Apache 2.0 emphasis if Vision B is paid-only. Decision pending.
- The hero artifact is a deliverable (a finished landing page, a finished email sequence, a finished product photo set), not a dashboard.

**If Bigouz wants both audiences:**
- This single page cannot serve both without dilution.
- The recommendation is two separate landing routes: `/dev` and `/business`, or `xroads.dev` and `xroads.studio` (or whatever the brand allows). Same engine, two front doors. The copy agent should be told this in advance.

---

## 15. What this framework deliberately does not do

- It does not include copy. The copy agent fills every block.
- It does not specify visual design (palette, typography, grid, motion). That is the Art Director's mandate, executed after copy is locked.
- It does not propose a CMS, stack, or hosting choice. That is downstream.
- It does not assume Vision A or Vision B is correct. Bigouz makes that call before copy starts.

---

## 16. Open decisions Bigouz must close before copy is written

1. Vision pick (A, B, or two front doors).
2. Primary ICP (one named persona).
3. Pricing variant (A: pure OSS, B: OSS + paid, C: OSS + sponsorship).
4. Whether the demo artifact will be a video loop, an animated terminal, or a static screenshot.
5. Whether the social proof strip has real users to cite, or pivots to maker credibility.
6. Domain / brand decisions (xroads.dev, xroads.studio, neurogrid.me/xroads, etc.).

Each of these is a 30-second decision. None require external research. The copy agent cannot start without them.
