# Data Processing Agreement (DPA) — Template

**Status:** TEMPLATE — instantiate per B2B customer
**Basis:** GDPR Art. 28

---

## 1. Parties

- **Controller:** _(customer name + address + rep)_
- **Processor:** Neurogrid SAS, France — _(address TBD)_

## 2. Subject matter & duration

Processor provides crossroads swift to Controller under the main services agreement. This DPA covers processing for the duration of that agreement.

## 3. Nature & purpose of processing

Operation of crossroads swift on behalf of Controller, including _(list: storage, AI inference, analytics)_.

## 4. Categories of data subjects

- End users of Controller's service who use crossroads swift
- Controller's employees with admin access

## 5. Categories of personal data

- Identification (email, name)
- Usage data (timestamps, interactions)
- _(fill product-specific categories)_

## 6. Processor's obligations

- Process only on documented Controller instructions
- Ensure confidentiality commitments from personnel
- Implement technical & organizational measures (Schedule A below)
- Assist Controller with data-subject rights requests
- Notify Controller of a personal-data breach within 48 hours
- Return or delete all personal data at end of service (Controller's choice)

## 7. Subprocessors

Processor uses the subprocessors listed in `privacy-policy.md`. Controller authorizes their use. 14 days' notice for any new subprocessor; Controller may object.

## 8. International transfers

Where transfers outside the EU occur, they rely on EU Standard Contractual Clauses (SCCs) 2021 or an adequacy decision.

## 9. Data subject rights

Processor assists Controller in responding to access / correction / deletion / portability requests within reasonable timeframes.

## 10. Security — Schedule A (minimums)

- Transport encryption: TLS 1.2+
- At-rest encryption: AES-256 (provider-level)
- Access: role-based, least-privilege, MFA for admin
- Database: row-level security where supported
- Backups: encrypted, offsite, tested restores
- Secrets: managed, rotated on leak

## 11. Audits

Controller may request a summary of security controls once per year. Physical audits by prior written agreement.

## 12. Termination

On termination, Processor returns or deletes personal data within 30 days (Controller's choice) and provides written confirmation.

---

## Signatures

Controller: _________________________ Date: ____________
Processor (Neurogrid SAS): _________________________ Date: ____________
