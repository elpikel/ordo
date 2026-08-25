defmodule Ordo.Repo.Migrations.AddMailboxToTickets do
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :mailbox_id, references(:mailboxes, on_delete: :nilify_all)
    end

    create index(:tickets, [:mailbox_id])
  end
end
