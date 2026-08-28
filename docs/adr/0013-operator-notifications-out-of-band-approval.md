# 0013 — Operator notifications with out-of-band approval

## Status
Accepted

## Context
Ordo drafts a reply the moment a message lands, but approval only happened inside
the inbox LiveView — the operator had to be looking at it. Shops asked to be
pinged when a draft is ready and to approve without opening the app: click a
button in an email, or reply "OK" on WhatsApp. The notification must carry enough
to decide — the customer's original message and Ordo's proposed reply.

## Decision
Reuse the pipeline's existing `draft_ready` transition and Oban; add one context,
two channels, and a tokened approval endpoint.

1. **Trigger + transport.** When `process/2` (email) or `process_review/2` (GBP)
   marks a ticket `draft_ready`, it calls `Notifications.enqueue/1`, which inserts
   an Oban job on a dedicated `:notifications` queue (per ADR-0007's fan-out
   spirit — off the pipeline/request path, retryable). The worker calls
   `deliver_new_draft/1`. Sending is **best-effort**: a failed email/WhatsApp is
   logged, not retried, so a flaky provider never re-spams the whole team.

2. **Opt-in, real tenants only.** Two tenant columns: `notify_enabled` (boolean,
   default **false** — off until the shop turns it on in settings) and
   `notify_whatsapp` (nullable E.164 number). Notifications fire only when
   `notify_enabled` and the tenant isn't the demo. Email goes to every user on the
   tenant; WhatsApp only if a number is set.

3. **One-click email approval via a signed token.** `Notifications.Token` signs
   the ticket id with `Phoenix.Token` (endpoint secret, 7-day expiry) — no DB row,
   tamper-proof, self-expiring. The email button is a GET to `/n/:token` that
   renders a confirmation page (safe from mail-scanner prefetch); the actual send
   is the POST from that page. The token *is* the authorization, so these routes
   run under no `:browser` pipeline — CSRF is moot, no login required.

4. **WhatsApp via Meta Cloud API, both directions.** Outbound send is a
   per-tenant adapter (`WhatsApp.Fake` for demo, `WhatsApp.CloudAPI` otherwise),
   same seam as GBP/BaseLinker, app creds in config. A message is `{:text, body}`
   or `{:template, name, lang, params}`: since every notification is
   business-initiated, when a template is configured (`WHATSAPP_TEMPLATE`) the
   adapter sends that pre-approved template — the only kind Meta accepts outside
   the 24-hour window — falling back to text in-session/for tests. Both variants
   carry the **full original message and proposed reply** (the operator decides
   from the message itself); template values are whitespace-collapsed and capped
   since Meta forbids newlines in them. Inbound is a
   webhook (`/webhooks/whatsapp`): Meta's GET verification handshake, and a POST
   whose `X-Hub-Signature-256` HMAC is verified against the raw body (cached by a
   `CacheBodyReader` wired into `Plug.Parsers`). Every outbound message carries a
   per-draft **reply code** (the ticket id): "OK 4821" targets exactly that draft,
   so replies are unambiguous even with several pending. Matching is scoped to the
   tenant whose `notify_whatsapp` equals the sender, then the explicit code, then
   the most recent `draft_ready` ticket for a bare "OK".

## Consequences
- A shop approves from wherever it already is; the inbox is no longer the only
  place a reply can go out. Same `approve_and_send/2` underneath, so audit/thread
  behaviour is identical to an in-app approval.
- New external dependency: Meta WhatsApp Cloud API, and an approved template must
  exist in the Meta console (body placeholders: customer name, original message,
  proposed reply, reply code) before business-initiated pings work outside the
  24-hour window. Text mode still serves in-session sends and tests.
- A bare "OK" still approves the *most recent* pending draft; the reply code makes
  it exact when it matters, and the email path is inherently unambiguous.
- Raw request bodies are now cached on every request (for webhook HMAC). Fine for
  this app (no large uploads); revisit if that changes.
