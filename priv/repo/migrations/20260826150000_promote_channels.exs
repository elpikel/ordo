defmodule Ordo.Repo.Migrations.PromoteChannels do
  use Ecto.Migration

  # Multi-channel inbox (ADR-0011): a channel is now a first-class row. The
  # `mailboxes` table becomes `channels` (email connection columns stay, null for
  # non-email types), gains a `type`/`name`/`config`, and the tenant's ad-hoc
  # `gbp_active` flag is replaced by a channels row of type "gbp". Tickets point
  # at a channel instead of a mailbox. Demo channels are re-seeded at runtime.
  def change do
    rename table(:mailboxes), to: table(:channels)

    alter table(:channels) do
      add :type, :string, null: false, default: "email"
      add :name, :string
      add :config, :map, null: false, default: %{}
      # Only email channels have an address; gbp/other types leave it null.
      modify :email, :string, null: true, from: {:string, null: false}
    end

    rename table(:tickets), :mailbox_id, to: :channel_id

    alter table(:tenants) do
      remove :gbp_active, :boolean, null: false, default: false
    end
  end
end
