# 0011 — Multi-channel inbox: one ticket stream, pluggable channels

## Status
Accepted

## Context
The inbox was hardwired to a single channel: email. `Ticket` carried
email-derived fields, `Message` carried RFC822 headers, and `Mailbox` was the
only source. But the product is "one inbox for everything a shop hears from
customers" — email today, Google Business Profile (GBP) reviews next, then
Allegro/Messenger/etc. Each source fetches items and lets the operator reply or
take an action (e.g. BaseLinker). We do not want a second inbox per channel.

## Decision
Keep **one `tickets` stream** and make the channel a property of the ticket, not
a separate table.

1. **Data model (additive, minimal).** Add two columns to `tickets`:
   - `channel_type` (string, default `"email"`) — `"email"`, `"gbp"`, …
   - `meta` (jsonb, default `{}`) — channel-specific data that doesn't deserve a
     column (review rating, author kind, external id, tracking, …).
   `mailbox_id` is already nullable; review tickets leave it null. `Message`
   is reused as-is: its unique `message_id` holds a namespaced external id
   (`"gbp:<review_id>"`), `in_reply_to` stays null for reviews. No new tables
   yet — a `channels`/connections table (OAuth creds, per-source config) is
   deferred until the first real (non-Fake) channel needs persisted credentials.

2. **Channel behaviour.** A `Ordo.Channels.Channel` behaviour with
   `fetch/1` and `send_reply/3`, mirroring the existing Fetcher/BaseLinker
   adapter pattern. One module per channel type; adapter chosen per tenant
   (`Fake` when `tenant.demo`, real `HTTP` otherwise). GBP ships a `Fake` (drives
   the demo from seeded reviews) and an `HTTP` stub (real Google API deferred).

3. **Ingestion & sending generalize.** `ingest_review/2` creates a ticket the
   same way `ingest_email/2` does (dedup by external id, customer Message,
   async classify + compose). `approve_and_send/2` dispatches the outbound reply
   to the ticket's channel module (email send stays deferred per ADR-0003; GBP
   "publishes" the reply — Fake no-ops).

4. **UI stays one design.** The list is channel-agnostic with a per-row channel
   indicator; the detail pane branches by `channel_type` (email thread + order
   receipt vs review card with stars). Negative reviews are never auto-published
   — human approval only, consistent with the Copilot send policy.

## Consequences
- One stream, one approve-flow, one PubSub topic — a new channel is a new
  adapter + a detail-pane branch, not a parallel subsystem.
- `Ticket`/`Message` carry a little channel-specific data in `meta`; truly shared
  fields (category, status, order_ref, sentiment, draft) stay columns.
- Real GBP (OAuth, Google API polling + publishing) and a credentials table are
  follow-ups behind the same behaviour; the Fake proves the seam first.
- Email behaviour is unchanged; the migration only adds columns with defaults.
