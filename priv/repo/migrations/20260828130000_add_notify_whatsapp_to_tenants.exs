defmodule Ordo.Repo.Migrations.AddNotifyWhatsappToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      # Operator notifications are opt-in — off until the shop turns them on.
      add :notify_enabled, :boolean, default: false, null: false
      # E.164 WhatsApp number the operator approves drafts from (nil = no WhatsApp notifications).
      add :notify_whatsapp, :string
    end
  end
end
