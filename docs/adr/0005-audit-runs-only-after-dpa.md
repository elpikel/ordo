# Audit runs only after a signed DPA

The real-inbox Audit runs **only after** a signed pilot agreement + DPA (umowa powierzenia). The pre-sale "wow" is the **Faza 0 demo on BaseLinker trial (synthetic) data**, never the shop's live inbox. LLM processing of audit data uses a **no-training / zero-retention** tier with the provider disclosed as a subprocessor; the audit corpus is pseudonymized in the report, encrypted at rest, tenant-isolated, and deleted N days after the pilot ends if no contract follows.

## Why

The Audit ingests 3–6 months of the shop's customers' personal data (names, addresses, order numbers, complaints). The shop is the controller and Ordo the processor, so there is no lawful basis to touch the live inbox before the DPA — which means the Audit **cannot** be the pre-sale artifact the spec implies. Reordering it (demo opens the door, Audit is the first thing delivered after signing) keeps the same sales impact while making the data processing lawful, and the no-train LLM tier prevents leaking customer PII into a third-party model.
