defmodule Ordo.Repo.Migrations.AddChannelToTickets do
  use Ecto.Migration

  # Multi-channel inbox (ADR-0011): tickets can come from email, GBP reviews, etc.
  # Additive only — existing rows default to the email channel.
  def change do
    alter table(:tickets) do
      add :channel_type, :string, null: false, default: "email"
      add :meta, :map, null: false, default: %{}
    end

    create index(:tickets, [:channel_type])
  end
end
