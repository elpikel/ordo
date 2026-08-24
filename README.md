# Ordo

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Support demo

The support panel is tenant-scoped at `/:tenant/inbox`, where `:tenant` is a slug or
numeric id. The seeded demo tenant (**OneDayMore**, slug `demo`) lives at
[`/demo/inbox`](http://localhost:4000/demo/inbox) and uses fake, seeded BaseLinker
data — click
**Importuj skrzynkę** to ingest ~24 test emails and watch them classify, resolve to
orders, and draft replies live.

The demo tenant is seeded automatically on first visit, but you can create/refresh
it explicitly (idempotent):

```bash
mix ordo.setup_demo                          # dev
bin/ordo eval "Ordo.Release.setup_demo()"    # prod (release — no Mix)
```

Classification and drafting use OpenAI when `OPENAI_API_KEY` is set; otherwise they
fall back to an offline heuristic (the badge shows `AI: fallback`).

```bash
export OPENAI_API_KEY=sk-...
mix phx.server
```

## BaseLinker integration

Order lookup is per-tenant behind the `Ordo.BaseLinker` behaviour:

* **Demo tenant** (`demo: true`) → `Ordo.BaseLinker.Fake`, seeded data. Nothing to configure.
* **Any other tenant** → `Ordo.BaseLinker.HTTP`, the real API (`connector.php`, `X-BLToken`).

Connect a real shop to a live BaseLinker account with:

```bash
mix ordo.connect_tenant <slug> <bl_token> [name] [support_email]
# e.g.
mix ordo.connect_tenant acme "BL-TOKEN-xxx" "Acme Foods" bok@acme.pl

mix ordo.connect_tenant acme "BL-TOKEN-xxx" "Acme Foods" bok@acme.pl
```

This creates (or updates) a non-demo tenant; its ticket processing then hits the
live BaseLinker read API (orders, packages, courier history, statuses). Its panel
is then at `/<slug>/inbox` (e.g. `/acme/inbox`).

**The token is stored encrypted at rest** (Cloak, `Ordo.Vault`). Dev/test use a key
from `config/dev.exs`/`config/test.exs`. **Production reads `CLOAK_KEY` (base64-encoded
32 bytes) and refuses to boot without it** — so it can never run with a weak key:

```bash
# generate once, keep secret, set in your prod env (e.g. Coolify)
mix run -e 'IO.puts(32 |> :crypto.strong_rand_bytes() |> Base.encode64())'
export CLOAK_KEY=...
```

Only **reads** are implemented so far; writes (returns, order changes) are deferred
(see [docs/adr/](docs/adr/) and [docs/failure-modes.md](docs/failure-modes.md)).

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
