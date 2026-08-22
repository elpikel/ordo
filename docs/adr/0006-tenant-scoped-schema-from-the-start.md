# Tenant-scoped schema from the start

Ordo carries `tenant_id` on tenant-owned rows (tickets, orders, policy) from the very first version, even though the demo seeds and shows exactly **one** Tenant (One Day More). There is no tenant switcher, no row-level isolation UI, and onboarding is a seed — but the boundary exists in the schema.

## Why

Retrofitting a tenant boundary onto a live single-tenant schema is expensive and error-prone (backfills, every query rewritten, leak risk during migration). Carrying `tenant_id` up front costs almost nothing now — one column and one seeded row — and makes "import One Day More's mailbox" mean something concrete: the pipeline reads *this tenant's* rules and orders. The explicit no-s (no switcher, no isolation UI, manual seed onboarding) keep it from turning into a multi-tenancy project before there's a second tenant to justify it.
