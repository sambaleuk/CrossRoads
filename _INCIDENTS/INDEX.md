# _INCIDENTS — crossroads swift

Append-only postmortem log. **Never edit a past incident file** — corrections go as new files with prefix `CORRECTION-` or in an "Addendum" section appended below a horizontal rule.

## Naming

`YYYY-MM-DD-slug.md` — one file per incident.

## Index

| Date | Severity | Slug | Root cause | Status |
|------|----------|------|------------|--------|
| _(none yet)_ | | | | |

## Severity rubric

- **SEV-1** — site down / data loss / payment broken / active security breach
- **SEV-2** — major feature broken for all users
- **SEV-3** — broken for a subset / degraded experience
- **SEV-4** — cosmetic / non-blocking

## Root-cause categories

`infra` · `deploy` · `external-api` · `code-bug` · `data` · `security` · `human`

## Postmortem template

```markdown
# YYYY-MM-DD — <slug>

**Severity:** SEV-?
**Duration:** <start> → <end> (<minutes>)
**Impact:** <users affected, $ at risk, data affected>
**Root cause category:** <from list>

## Timeline

- `HH:MM` — <what happened / what was noticed>
- `HH:MM` — <next event>

## Root cause (Five Whys)

1. Why did X happen? — …
2. Why? — …
3. Why? — …
4. Why? — …
5. Why? — …

→ **Real root cause:** …

## What worked

…

## What didn't work

…

## Preventive actions

- [ ] <concrete change in code / process / runbook>
- [ ] <who owns it / when>

## Runbook updates

- Updated `<path to runbook>` with: …
- (or: no runbook existed — created `<new path>`)
```

## Quarterly pattern review

Every 3 months: scan incidents, look for repeat categories. If the same root-cause category shows up 3× — that's a systemic issue, promote to a pattern in `00_MAIN/patterns/`.
