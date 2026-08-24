defmodule Ordo.Repo.Migrations.CreateMailboxes do
  use Ecto.Migration

  def change do
    create table(:mailboxes) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :auth_strategy, :string, null: false, default: "imap_password"
      add :email, :string, null: false

      # IMAP (fetch)
      add :imap_host, :string
      add :imap_port, :integer, default: 993
      add :username, :string
      # Encrypted at rest via Cloak (Ordo.Encrypted.Binary).
      add :password, :binary

      # SMTP (send — ADR-0003)
      add :smtp_host, :string
      add :smtp_port, :integer, default: 587

      add :folder, :string, default: "INBOX"

      # Polling cursor
      add :uidvalidity, :integer
      add :last_uid, :integer, default: 0

      add :active, :boolean, null: false, default: true
      add :last_polled_at, :utc_datetime_usec
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:mailboxes, [:tenant_id])
    create index(:mailboxes, [:active])
  end
end
