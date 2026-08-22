defmodule Ordo.Repo.Migrations.AddTenantsAndPolicy do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :support_email, :string
      add :signature, :string
      add :couriers, {:array, :string}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])

    create table(:policy_facts) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :label, :string, null: false
      add :value, :string, null: false
      add :unit, :string
      add :category, :string
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:policy_facts, [:tenant_id])

    alter table(:tickets) do
      add :tenant_id, references(:tenants, on_delete: :delete_all)
    end

    create index(:tickets, [:tenant_id])
  end
end
