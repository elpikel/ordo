defmodule Ordo.Support.Message do
  @moduledoc "One email in a Ticket thread — from the customer or from Ordo."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ordo.Support.Ticket

  schema "messages" do
    field :role, :string
    field :body, :string

    belongs_to :ticket, Ticket

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :body, :ticket_id])
    |> validate_required([:role])
    |> validate_inclusion(:role, ["customer", "ordo"])
  end
end
