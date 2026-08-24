# Email intake: INBOX only, dedup by Message-ID, thread by References

The live poller reads the **INBOX only**. Each fetched message goes through
`Support.ingest_email/2`: a **machine-mail header filter** (drop bounces
`Return-Path: <>`, auto-replies `Auto-Submitted: auto-*`, list mail
`List-Id`/`List-Unsubscribe`), **dedup by `Message-ID`** (unique constraint), then
**thread by `References`/`In-Reply-To`** — append to the matching Ticket and reopen
it, otherwise create a new one — before running the existing classify/compose
pipeline. A one-line belt-and-braces skips any message whose `From` is the mailbox's
own address.

## Why

- **No own-outbound loop guard is needed.** Ordo's replies go to the shop's **Sent**
  folder (ADR-0003), never INBOX, so they cannot re-enter as tickets. The things that
  *do* come back — customer replies (wanted) and bounces/auto-replies (dropped as
  machine mail) — are already handled. Reading INBOX-only makes the loop structurally
  impossible, so the Message-ID-tracking guard from the original design is dropped
  rather than deferred. The `From`-self skip covers only oddball servers that copy
  sent mail into INBOX.
- **Sent is touched only by the future Audit**, a batch import that pairs
  customer↔shop history and never creates live tickets — not by the poller.
- **Message-ID dedup** is the cheapest, race-free idempotency for re-polls / UID
  overlap.

## Deferred

Per-shop **sender allow/deny** (marketplace notifications, courier mail, supplier
invoices) is a noise problem, not a correctness one, and needs onboarding config — so
it is not built here. See [failure-modes.md](../failure-modes.md).
