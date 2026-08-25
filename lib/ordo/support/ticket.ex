defmodule Ordo.Support.Ticket do
  @moduledoc "A conversation thread with a customer (see CONTEXT.md: Ticket)."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ordo.Support.{Mailbox, Message, Tenant}

  schema "tickets" do
    belongs_to :tenant, Tenant
    belongs_to :mailbox, Mailbox

    field :customer_name, :string
    field :customer_email, :string
    field :subject, :string
    field :category, :string
    field :language, :string
    field :order_ref, :string
    field :sentiment, :string
    field :status, :string, default: "new"
    field :draft, :string
    field :order, :map
    field :resolution_seconds, :integer
    field :answered_at, :utc_datetime_usec

    has_many :messages, Message, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :tenant_id,
      :mailbox_id,
      :customer_name,
      :customer_email,
      :subject,
      :category,
      :language,
      :order_ref,
      :sentiment,
      :status,
      :draft,
      :order,
      :resolution_seconds,
      :answered_at
    ])
    |> validate_required([:customer_email, :subject])
  end
end
