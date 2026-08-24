defmodule Ordo.Repo.Migrations.AddMessageThreading do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :message_id, :string
      add :in_reply_to, :string
    end

    # Dedup by Message-ID. Multiple NULLs are allowed in Postgres unique indexes,
    # so the demo's artificial messages (no Message-ID) don't collide.
    create unique_index(:messages, [:message_id])
  end
end
