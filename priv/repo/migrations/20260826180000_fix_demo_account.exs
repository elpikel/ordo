defmodule Ordo.Repo.Migrations.FixDemoAccount do
  use Ecto.Migration

  # Repair demo accounts seeded before the gbp channel existed: ensure the gbp
  # channel, re-home orphaned review tickets (null channel_id) onto it, and seed
  # any missing reviews so the Google channel is populated. Idempotent via
  # fix_demo_account!/0. Deterministic offline, no Cloak fields — release-safe.
  def up do
    unless Code.ensure_loaded?(Mix) and Mix.env() == :test do
      Ordo.Support.fix_demo_account!()
    end
  end

  def down, do: :ok
end
