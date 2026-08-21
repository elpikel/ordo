# Ordo

Ordo reads a merchant's support inbox, pulls order context from BaseLinker, drafts a reply, and (with a human's approval) sends it. This glossary fixes the language of that domain.

## Language

**Ticket**:
One conversation thread with a customer, keyed by the normalized root email (Message-ID/References) plus the customer address. Reopenable: it returns to the start of its lifecycle when a new customer message arrives after a reply was sent. Lifecycle: `New → Draft ready → Awaiting send → Answered` (and back to `New` on reopen). "Answered" is not terminal.
_Avoid_: Mail, Message (those are a single email), Wątek, Zgłoszenie, Case.

**Reply**:
A single outbound answer sent to the customer. The unit metrics are counted per — one draft→send cycle is one sample for "edited / not-edited" and response-time stats. A Ticket can accumulate several Replies over its life.
_Avoid_: Response.

**Focus order**:
The single BaseLinker order a Ticket is currently about (0..1). Resolved by precedence — an order number extracted from the email wins over an email-address match — and re-resolvable on reopen or human correction. A draft records which Focus order it used.
_Avoid_: The order, matched order.

**Candidate set**:
The orders returned when resolving a Ticket to an order by customer email — may be 0, 1, or N. Never auto-bound when N > 1: the human picks, or the reply asks the customer to confirm the order number.
_Avoid_: Search results, matches.

**Read action** / **Write action**:
The two classes every BaseLinker method falls into. A Read has no side effects on the merchant's data (e.g. `getOrderPackages`, `getInvoiceFile`) and may run anytime to build context. A Write mutates the merchant's BaseLinker (e.g. `addOrderReturn`, `setOrderFields`, `setOrderStatus`) and never runs before a human approves.
_Avoid_: Query/command, fetch/mutation.

**Pending action**:
A staged BaseLinker Write bound to a Ticket, shown in the panel but not executed during drafting. It runs only on approval, atomically with the send — so the draft *promises* an artifact (e.g. a return label) that approval *creates*. On reject or edit, it never runs.
_Avoid_: Queued action, staged write.

**Draft policy**:
A fixed per-category property saying how much Ordo pre-fills a reply: `full draft`, `draft + prepared Pending action` (CANCELLATION), or `no draft` (OTHER — the human writes, with BL context shown). Independent of Send policy.
_Avoid_: Mode (that's Send policy).

**Send policy**:
The per-category axis governing who may send a reply, and the only axis that gets promoted over time. Values: **Copilot** (a human approves every send — the MVP default for all categories), **Autopilot** (Ordo sends without a human), **Blocked** (pinned at human forever — COMPLAINT and money refunds). The taxonomy's "Tryb startowy" is really each category's Send-policy *ceiling*.
_Avoid_: Mode, automation level.

**Override**:
An Autopilot-era signal that forces a Ticket to human sending regardless of Send policy. Derived from concrete pipeline conditions (unresolved/ambiguous order, OTHER, missing Policy fact, composer fallback, angry sentiment, off-cell language) — never a model-reported confidence score. In the MVP there is no Override and no confidence gate: every reply is Copilot, so a human approving each one is the safety mechanism.
_Avoid_: Confidence threshold, exception.

**Mailbox connection**:
A tenant's link to their own email mailbox — the source Ordo polls and the identity it sends as. Has a pluggable auth strategy (`imap_password` default; `oauth_gmail` / `oauth_graph` adapters when a provider forces it). Ordo always sends *through* this connection, so replies carry aligned SPF/DKIM/DMARC and file into the shop's own Sent folder.
_Avoid_: Email account, inbox integration.

**Policy**:
A shop's accepted, versioned set of support facts (return window, return-shipping cost, complaint procedure, dispatch hours). The audit *proposes* it from historical replies, but the composer may use it only after the shop accepts/edits it. Versioned, so a wrong answer is traceable to the accepted version that produced it.
_Avoid_: Rules, knowledge base, FAQ.

**Policy fact**:
A single accepted statement within a Policy (e.g. "return window 14 days"). Cited by id + version in a draft's sources. Ranks below live BL data and is never generalized to fill a gap.
_Avoid_: Rule, setting.

**Take-over**:
The human discards Ordo's draft and writes the reply themselves ("Przejmij"). A stronger negative signal than an edit, tracked separately and excluded from the No-edit rate numerator.
_Avoid_: Reject, override.

**No-edit rate**:
The promotion metric per **(category × language)**: the share of Replies in that cell sent byte-identical to Ordo's draft (whitespace-normalized, signature templated out). Any change to the normalized body counts as an edit; take-overs are failures. A cell may be considered for Autopilot at ≥30 samples and ≥90% no-edit over two weeks. Keying by language means a rare language never auto-sends until it has independently earned it.
_Avoid_: Accuracy, approval rate.

**Verification language**:
A shop's primary language, in which the human verifies drafts. Any Ticket not in it is shown glossed both ways — the customer's message and Ordo's draft each translated into the Verification language — so Copilot works in any language while the human still understands what they approve.
_Avoid_: Default language, locale.

**Intake filter**:
The pre-classifier gate deciding whether inbound mail becomes a Ticket at all. Drops Ordo's own outbound (never creating a Ticket from a message Ordo sent — this closes the send/poll feedback loop by construction), machine mail (bounces, auto-replies, list mail), and non-support senders. Only what survives reaches the classifier.
_Avoid_: Spam filter, pre-processor.

**no_action**:
A classifier outcome for a human message that needs no reply (a closing courtesy like "dziękuję"). It appends to the thread and auto-closes without a Draft — a reopen that demands no Reply and is excluded from the No-edit rate.
_Avoid_: Ignored, closed.

**Delivery failed**:
A Ticket state entered when a sent Reply hard-bounces. Excluded from resolved / deflection / response-time metrics until a human resolves it (another channel, corrected address). Encodes the rule that "sent" is not "delivered."
_Avoid_: Failed, error.

**Bounce reconciler**:
The path that matches an inbound DSN (bounce) to the Reply that caused it, by the failed message's Message-ID, and flips its Ticket to Delivery failed. Distinct from the Intake filter, which merely stops the bounce from creating a new Ticket.
_Avoid_: Bounce handler.

**Audit**:
Ordo's first post-signature deliverable: an import of 3–6 months of the shop's inbox, paired customer↔shop, classified, and turned into a report (volume, category mix, response times, top questions, automatability estimate) plus a proposed Policy. Processes real customer personal data, so it runs only after the DPA — the demo opens the door, the Audit is delivered once the shop signs.
_Avoid_: Analysis (the report is one output of the Audit).

**Status map**:
A per-shop mapping from BaseLinker's custom order-status ids to Ordo's fixed semantic enum (`new / processing / dispatched / delivered / cancelled / returned`), captured at onboarding. An unmapped or unknown status fails safe: write actions refuse and escalate rather than assume pre-dispatch.
_Avoid_: Status list, state mapping.

**Dispatch boundary**:
The semantic `dispatched` state in the Status map — the line past which write actions (ORDER_CHANGE, CANCELLATION) are refused. Determines whether courier tracking exists to report for PACKAGE_STATUS.
_Avoid_: Shipped flag, cutoff.
