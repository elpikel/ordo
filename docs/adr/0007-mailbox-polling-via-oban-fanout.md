# Mailbox polling via Oban fan-out, poll-based IMAP

Ordo fetches tenant mail by **polling**, not persistent connections. A `Mailbox`
belongs to a Tenant (1:many), stores the IMAP/SMTP connection with the **password
encrypted at rest** (Cloak) and a **UID cursor** (`uidvalidity` + `last_uid`). An
Oban **Cron** job fires every minute and only **fans out one unique `PollMailbox`
job per active mailbox**; those drain through a bounded `:mailbox` queue. Fetching
sits behind an `Ordo.Mailboxes.Fetcher` behaviour with `Fake` (demo/tests) and a
thin hand-rolled `IMAP` adapter (`LOGIN`/`SELECT`/`UID SEARCH`/`UID FETCH`).

## Why

- **Fan-out over one loop**: a single cron job looping all mailboxes lets one slow
  or hung IMAP server block every tenant, with all-or-nothing retries. Per-mailbox
  unique jobs give isolation (one bad box retries itself, records `last_error`,
  blocks no one) and the queue caps concurrent IMAP connections.
- **Poll over persistent (Yugo)**: the maintained Elixir IMAP client is a
  persistent per-mailbox GenServer (IDLE). That's a different architecture than the
  Oban poll model and pulls fetching out of Oban. A thin poll-based client keeps the
  architecture coherent, fully testable behind the behaviour, and swappable for Yugo
  later if the protocol code gets painful. Cost: ~200 lines of IMAP we own.
- **UID cursor over "seen" flags**: `UID FETCH (last_uid+1):*` after checking
  `UIDVALIDITY` is race-free and re-poll-safe, with no server-side flag mutation.
- **Encrypted password only**: host/username/ports aren't secret and stay queryable;
  the password reuses the existing `Ordo.Encrypted.Binary` (Cloak).

The demo tenant has no `Mailbox`, so it is never polled and keeps its artificial inbox.
