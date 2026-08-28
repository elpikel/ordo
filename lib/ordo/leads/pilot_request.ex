defmodule Ordo.Leads.PilotRequest do
  @moduledoc """
  A prospect who left their email through the "Request a slot" form on the
  landing page, asking to join the pilot program.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "pilot_requests" do
    field :email, :string
    field :locale, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pilot_request, attrs) do
    pilot_request
    |> cast(attrs, [:email, :locale])
    |> update_change(:email, &String.trim/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
  end
end
