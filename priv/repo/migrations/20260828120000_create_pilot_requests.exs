defmodule Ordo.Repo.Migrations.CreatePilotRequests do
  use Ecto.Migration

  def change do
    create table(:pilot_requests) do
      add :email, :string, null: false
      add :locale, :string

      timestamps(type: :utc_datetime)
    end

    create index(:pilot_requests, [:email])
  end
end
