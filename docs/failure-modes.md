# Failure modes — known risks, deferred

The demo MVP assumes **happy paths everywhere**. This is the list of places the real product will break, captured now so we don't rediscover them later. None are handled in the demo.

## Inbox & threading
- Poller re-ingests Ordo's own sent mail → reply-to-self **feedback loop**.
- Bounces / auto-replies / newsletters / marketplace & courier notifications become tickets → noisy panel, polluted metrics.
- Mis-threading (subject changed, missing References) → duplicate or merged tickets.
- Duplicate ingestion (UID re-read) → duplicate tickets.

## Order resolution (email → BaseLinker)
- **Zero matches** — customer emails from a different address than they ordered with.
- **N matches** — several orders per email; picking the wrong one → answer about the wrong order.
- Wrong / stale order number extracted from the email body.

## BaseLinker
- Custom per-shop statuses **unmapped** → wrong "shipped" judgment → write-guard bypass (edit a shipped order) or wrong tracking answer.
- New status added after onboarding → unmapped.
- BL API down / rate-limited / slow → no context to ground a draft.
- **Courier status history empty** (trial accounts, or before first scan) → "where's my parcel" has no data.

## Composer correctness
- Confident but **wrong** answer from a stale/misextracted Policy fact.
- Missing Policy fact → must fall back to "przekazuję do zespołu."
- Mistranslated Policy fact when replying in another language.

## Writes (returns, order changes, cancellations)
- Write fires but reply never sends → phantom state in the merchant's BL.
- Non-idempotent write retried → **double return / double status change**.
- Dispatch-boundary guard wrong → mutate an already-shipped order.
- Return eligibility (window, condition) not actually checked.

## Sending & delivery
- SPF/DKIM/DMARC misalignment → replies land in spam.
- **Hard bounce** → ticket reads "resolved" but customer got nothing → inflated case-study numbers.
- Double-send on retry → customer gets two emails.
- Provider send limits / Sent-folder append fails.

## Classification
- Misclassification → wrong category, wrong actions/draft.
- Language or sentiment mis-detected (angry customer not caught).

## Metrics integrity
- No-edit counted on cosmetic edits → wrong promotion signal.
- Language-blind promotion (Autopilot era) → auto-send in an unproven language.
- Bounced replies counted as resolved.

## Multi-tenancy, security, RODO
- **No authentication.** Every route is public — the inbox (`/:tenant/inbox`) and
  especially the settings page (`/:tenant/settings`), which lets anyone set a shop's
  BaseLinker token and IMAP passwords. **Auth is a hard prerequisite before any real
  shop connects.** Encryption at rest protects a DB leak, not an open URL.
- Cross-tenant data or secret leakage.
- Ordo operators' access to customer PII (needs DPA + access log).
- LLM subprocessor retention/training on customer data.
- Audit run before a signed DPA (no lawful basis).
- Retention window not enforced; tokens/creds at rest.

## Autopilot (future)
- Promotion on thin or biased evidence.
- Override gated on self-reported model confidence (confidently wrong).
- Errors invisible in a language the merchant can't read.
