defmodule Ordo.Repo.Migrations.SeedDemoTenant do
  use Ecto.Migration

  # Data seed: create the demo tenant, its Policy/mailboxes, and an activated demo
  # user with a password, so the public /demo login (and manual log-in) works
  # immediately after deploy. Idempotent via ensure_demo_tenant!/0 — safe to run
  # even if the demo was already seeded at runtime. Touches no Cloak-encrypted
  # fields, so it is safe under release migrations (Vault not started).
  def up do
    # Skip in the test env — fixture rows in the test DB break isolation. Mix is
    # unavailable in a release, so prod (and local dev) still seed.
    unless Code.ensure_loaded?(Mix) and Mix.env() == :test do
      Ordo.Support.ensure_demo_tenant!()
    end
  end

  def down do
    :ok
  end
end
