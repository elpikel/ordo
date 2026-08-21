# Send through the shop's own mailbox (aligned identity)

Ordo sends replies **through the shop's own mailbox** (their SMTP, their credentials) rather than from Ordo's infrastructure with a `From: shop` header. The Mailbox connection is a pluggable auth abstraction — `imap_password` by default, `oauth_gmail` / `oauth_graph` as adapters added when a provider forces it.

## Why

Sending from our infra with a forged From fails the shop's SPF/DKIM/DMARC, so replies land in spam or get rejected — the "47 s resolved" is worthless if the customer never sees it — and asking the shop to edit DNS breaks the "nothing installed, nothing migrated" promise. Sending through their provider means the mail genuinely originates there: identity aligns (inbox, not spam), and the sent reply files into the shop's own Sent folder, so staff keep full visibility and can take over any thread. This reinforces the core principle: use what they already have.

## Open question

The pilots' provider mix is unconfirmed. Microsoft 365 disables basic-auth IMAP/SMTP by default, which would force the `oauth_graph` adapter into the MVP for such a pilot. Gmail and Polish hosting mailboxes (home.pl, seohost) work with `imap_password` today.
