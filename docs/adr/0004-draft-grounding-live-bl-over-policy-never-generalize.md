# Draft grounding: live BL over accepted Policy, never generalize

A draft is grounded in a strict precedence: **live BaseLinker data for this order > the shop's accepted Policy fact > escalate ("przekazuję do zespołu")**. The composer may use Policy facts only from a shop-**accepted, versioned** Policy — never raw LLM extractions from the audit — and every draft cites its sources at fact level (order fields; Policy fact by id + version).

## Why

"Don't invent facts" is not enough, because the dangerous failure is a *sourced, plausible, wrong* fact: an LLM extracts "30-day returns" from an old email, the shop has since moved to 14 days, and the composer states it confidently — technically "from the provided data," yet the shop is now on the hook. Forcing human acceptance turns extractions into owned, versioned truth; putting live BL data above Policy stops a per-order generalization ("ships in 24h") from overriding what actually happened to *this* order; and fact-level citations make every claim auditable and traceable to the version that produced it.
