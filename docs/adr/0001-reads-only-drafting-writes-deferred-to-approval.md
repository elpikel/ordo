# Reads-only drafting; BaseLinker writes deferred to approval

Ordo's taxonomy mixes read and write BaseLinker calls per category. We decided that **drafts are built exclusively from Read actions**, and any Write (e.g. `addOrderReturn`, `setOrderFields`, `setOrderStatus`) is staged as a **Pending action** that executes only on human approval, atomically with sending the reply. Artifacts that a Write produces (like a return label) are generated at send-time, not draft-time.

## Why

The naive path calls the Write while drafting — e.g. `addOrderReturn` to fetch the label to attach. But in Copilot the human may reject or edit the draft, which would leave a **phantom return** in the merchant's live BaseLinker, potentially triggering their downstream automations (stock, accounting, refund flags). Mutating a client's system for a reply that never goes out is unacceptable. Deferring writes to approval makes reject/edit side-effect-free, and makes the eventual Autopilot promotion of a write-category an explicit, auditable step (auto-executing the Pending action), which is why write-categories earn Autopilot last and refunds/complaints never.
