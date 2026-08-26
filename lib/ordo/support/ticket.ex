defmodule Ordo.Support.Ticket do
  @moduledoc "A conversation thread with a customer (see CONTEXT.md: Ticket)."
  use Ecto.Schema

  import Ecto.Changeset

  alias Ordo.Support.Channel
  alias Ordo.Support.Message
  alias Ordo.Support.Tenant

  schema "tickets" do
    belongs_to :tenant, Tenant
    belongs_to :channel, Channel

    field :meta, :map, default: %{}
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
      :channel_id,
      :meta,
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
    |> validate_required([:subject])
    |> validate_customer_contact()
  end

  @doc """
  The ticket's channel type, read from its (preloaded) channel. Falls back to
  `"email"` when the channel isn't loaded or was removed — the inbox renders such
  a ticket as a plain email thread.
  """
  def channel_type(%__MODULE__{channel: %Channel{type: type}}), do: type
  def channel_type(_ticket), do: "email"

  # Every ticket needs *some* way to name the customer: email (support mail) or a
  # display name (a review author who has no email).
  defp validate_customer_contact(changeset) do
    email = get_field(changeset, :customer_email)
    name = get_field(changeset, :customer_name)

    if blank?(email) and blank?(name) do
      add_error(changeset, :customer_email, "or customer_name is required")
    else
      changeset
    end
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end
