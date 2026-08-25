# Tenant isolation by construction — no slug in authenticated URLs

Authenticated routes carry **no tenant slug**: `/inbox`, `/inbox/:id`, `/settings`. The tenant is always the logged-in User's, read from `current_scope.tenant`. Cross-tenant access is impossible **by construction** — there is no other-tenant URL to express, so no per-route guard can be forgotten. The existing `/:tenant/...` routes are replaced; ticket ids and the `?mbx=` filter drop the slug.

The **demo is not a public unauthenticated carve-out**. It is a seeded, **activated demo User** on the demo tenant, reached by a one-click public **"demo login"** route that signs that User in and redirects to `/inbox`. So the demo flows through the same auth + scope path as every real tenant.

## Why

Isolation-by-construction beats isolation-by-check: an authorization hook that must run on every tenant route can be forgotten on the next route added; a URL that can't name another tenant can't leak one. Deriving the tenant from the session (not the URL) also collapses demo and real tenants into a single code path. The cost is reworking the slug-based URLs built earlier — worth it for a security boundary.

## Consequence / caveat

All demo visitors share the single demo tenant, so concurrent import/clear can interfere. Acceptable for a driven pitch; per-visitor demo sandboxes are a later option.
