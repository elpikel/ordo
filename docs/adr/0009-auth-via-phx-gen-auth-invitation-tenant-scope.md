# Auth via phx.gen.auth, invitation-only, tenant in the scope

Authentication is built on Phoenix's `mix phx.gen.auth` (Accounts context, User schema, **bcrypt** hashing, session + token machinery, and the 1.8 **Scope** that threads `current_scope`) rather than hand-rolled. We adapt the generated system: a **User belongs_to a Tenant**, the **Scope carries the Tenant** (not just the user), public **self-registration is removed** in favour of invitation-only account creation, and **password login + password reset are kept**.

## Why

Auth is the one place where rolling your own is a real footgun — session fixation, token expiry, timing-safe comparisons, CSRF, reset-token leakage. The generator is battle-tested and gives login/logout, update-password, and forgot-password essentially for free. Its Scope threading is the natural seam for per-tenant authorization (a request knows *who* and *which tenant* in one place), which is exactly what "a User sees only their Tenant's data" needs. We diverge from the generator only where the product demands it — invites instead of open sign-up, password instead of magic-link-only.
