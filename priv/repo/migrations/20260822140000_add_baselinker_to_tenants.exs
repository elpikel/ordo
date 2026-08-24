defmodule Ordo.Repo.Migrations.AddBaselinkerToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      add :demo, :boolean, null: false, default: false
      # Encrypted at rest via Cloak (Ordo.Encrypted.Binary).
      add :bl_token, :binary
    end
  end
end
