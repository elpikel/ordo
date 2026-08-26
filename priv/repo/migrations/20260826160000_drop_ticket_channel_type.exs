defmodule Ordo.Repo.Migrations.DropTicketChannelType do
  use Ecto.Migration

  # A ticket's channel type is now derived from its channel row (ADR-0011); the
  # denormalized `channel_type` column is redundant. `channel_id` stays nullable
  # (on_delete: :nilify_all) — a ticket whose channel was removed reads as email.
  def change do
    drop index(:tickets, [:channel_type])

    alter table(:tickets) do
      remove :channel_type, :string, default: "email"
    end
  end
end
