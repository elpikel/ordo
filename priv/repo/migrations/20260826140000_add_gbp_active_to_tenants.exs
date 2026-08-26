defmodule Ordo.Repo.Migrations.AddGbpActiveToTenants do
  use Ecto.Migration

  # Multi-channel inbox (ADR-0011): the Google Business Profile reviews channel
  # only appears in the inbox filter for tenants that have the integration on.
  # A boolean marker until a real channels/credentials table lands.
  def change do
    alter table(:tenants) do
      add :gbp_active, :boolean, null: false, default: false
    end
  end
end
