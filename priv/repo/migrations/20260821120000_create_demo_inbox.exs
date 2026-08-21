defmodule Ordo.Repo.Migrations.CreateDemoInbox do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      add :customer_name, :string
      add :customer_email, :string
      add :subject, :string
      add :category, :string
      add :language, :string
      add :order_ref, :string
      add :sentiment, :string
      add :status, :string, null: false, default: "new"
      add :draft, :text
      add :order, :map
      add :resolution_seconds, :integer
      add :answered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:messages) do
      add :ticket_id, references(:tickets, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :body, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:ticket_id])
  end
end
