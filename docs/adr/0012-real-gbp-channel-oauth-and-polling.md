# 0012 — Real GBP channel: OAuth connect + review polling

## Status
Accepted

## Context
ADR-0011 shipped the multi-channel seam with a GBP `Fake` (drives the demo from
seeded reviews) and an `HTTP` stub, and deferred "real GBP (OAuth, Google API
polling + publishing) and a credentials table" as a follow-up. The `HTTP`
adapter now talks to the My Business v4 reviews API, so the two remaining gaps
are: real tenants have no way to *connect* a profile (run consent, obtain a
refresh token, discover which account/location to read), and connected profiles
are never *polled* — `fetch/1` only runs on the manual demo-import path.

## Decision
Reuse what ADR-0011 already built (the `channels` row, the `Channel` behaviour,
the Oban fan-out) rather than adding parallel machinery.

1. **Credentials live on the `channels` row — no new table.** The encrypted
   `password` column (already there for IMAP) holds the OAuth **refresh token**;
   `config` (jsonb) holds the profile resource ids (`"account"`, `"location"`).
   The OAuth app id/secret are process-wide config
   (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`). This retires ADR-0011's
   "credentials table is a follow-up" — one secret per channel doesn't earn a
   table.

2. **Connect flow = standard OAuth authorization-code, in a plain controller.**
   `OrdoWeb.GoogleOAuthController` redirects to Google's consent screen
   (`access_type=offline`, `prompt=consent` so a refresh token is always
   returned; a random `state` in the session guards CSRF). The callback exchanges
   the code, discovers the first account + location via the Account Management /
   Business Information v1 APIs, and upserts the tenant's `gbp` channel. OAuth is
   a full-page redirect, so it lives in a controller, not the settings LiveView;
   the "Connect" button becomes a link to `/oauth/google/authorize`. All Google
   calls go through `Ordo.Channels.Gbp.OAuth`, which shares the adapter's
   `:gbp_req_options` injection so tests stub it with `Req.Test`.

3. **Polling reuses the Oban fan-out (ADR-0007).** `ScheduleJob` (cron, every
   minute) already fans out one job per active email channel; it now also fans
   out one `PollReviews` job per active gbp channel. `list_active` gates on
   `demo == false` (real credentials only) and, for gbp, on a refresh token
   being present, so unconfigured or demo profiles are never polled. `PollReviews`
   calls `Gbp.fetch/1` and routes each review through the existing
   `receive_review/2` (dedup by `gbp:<review_id>`, async classify + compose),
   then stamps the polling cursor — exactly the shape of `PollChannel`.

4. **Best-effort, non-blocking, with one signal that matters.** A transient
   Google error degrades a poll to a no-op (and lets Oban retry); the adapter
   doesn't crash the job. The exception is a **revoked/expired refresh token**
   (`invalid_grant`) — auth is a one-time interactive step, but the token can die
   (revocation, 6-month idle, or an unpublished OAuth app's 7-day cap). That
   surfaces as `{:error, :auth}`: the worker writes an `"auth"` marker to the
   channel's `last_error`, `list_active_reviews` drops the profile from the poll
   set (no point hammering a dead token), and settings shows a red "RECONNECT"
   with a one-click link. A fresh connect clears the marker and resumes polling.

5. **Discovery picks the first account + location** — enough for a single-profile
   pilot; multi-location selection is a follow-up. Response shapes follow
   Google's docs and want verification against a real profile.

## Consequences
- A real tenant can self-connect a profile end to end; reviews then flow into the
  same ticket stream and approve/publish path as email — no new subsystem.
- Two Google API surfaces are now depended on (Account Management + Business
  Information for discovery, My Business v4 for reviews); the v4 reviews API in
  particular is legacy and access is gated by Google approval.
- Picking the first account/location will mispick for tenants with several; the
  connect UI stays "one click" until a customer needs the chooser.
- No credentials table: if a second per-channel secret ever appears (e.g. a
  separate publish scope), revisit whether `password`/`config` still suffice.
