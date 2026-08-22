defmodule Ordo.Support.Tenant do
  @moduledoc "A shop Ordo serves and the isolation boundary for its data (see CONTEXT.md: Tenant)."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ordo.Support.{PolicyFact, Ticket}

  schema "tenants" do
    field :slug, :string
    field :name, :string
    field :support_email, :string
    field :signature, :string
    field :couriers, {:array, :string}, default: []

    has_many :policy_facts, PolicyFact, preload_order: [asc: :position]
    has_many :tickets, Ticket

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:slug, :name, :support_email, :signature, :couriers])
    |> validate_required([:slug, :name])
    |> unique_constraint(:slug)
  end
end
