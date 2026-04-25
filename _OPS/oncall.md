# On-call — crossroads swift

Solo-founder posture. No 24/7 coverage.

## Response windows (Europe/Paris)

| Window | Response | Scope |
|--------|----------|-------|
| Mon–Fri 09:00–19:00 | < 30 min | everything |
| Mon–Fri 19:00–23:00 | < 2 h | critical only |
| Sat–Sun 09:00–20:00 | best-effort | critical only |
| 23:00–09:00 | no response | critical handled next morning |

## "Critical" =

- Site / app is down for paying users
- Payment flow is broken
- Data loss is possible or ongoing
- Security breach (leaked secret, unauthorized access, compromised account)

Everything else is not critical and waits for next working window.

## Escalation

There is no escalation. Birahim is the escalation. If Birahim is unavailable, the system waits — that's the accepted trade-off of solo-founder posture. This changes when the first hire lands.

## Vacation

Before going offline > 48 h:

- [ ] Auto-responder set on support inbox
- [ ] Status page (if any) updated to note reduced-coverage window
- [ ] Feature flags for anything experimental: OFF
- [ ] No deploys in the 48 h before departure
- [ ] AI / paid API cost caps verified tight

## After an incident

Every SEV-1 or SEV-2 requires a postmortem in `_INCIDENTS/` within 7 days. SEV-3 is optional but encouraged if patterns recur.
