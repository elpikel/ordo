defmodule Ordo.Repo.Migrations.SeedDemoInbox do
  use Ecto.Migration

  # Data seed: ensure the demo tenant has its gbp channel and a populated inbox
  # (tickets + messages for the demo emails and Google reviews), so a fresh deploy
  # shows the demo without clicking "Import". Idempotent via seed_demo_inbox!/0.
  # The demo pipeline (Ordo.AI + demo BaseLinker) is deterministic offline and no
  # tickets/messages touch Cloak-encrypted fields, so it is safe under release
  # migrations (Vault not started).
  def up do
    # Skip in the test env — fixture rows in the test DB break isolation. Mix is
    # unavailable in a release, so prod (and local dev) still seed.
    unless Code.ensure_loaded?(Mix) and Mix.env() == :test do
      Ordo.Support.seed_demo_inbox!()
    end
  end

  def down do
    :ok
  end
end
