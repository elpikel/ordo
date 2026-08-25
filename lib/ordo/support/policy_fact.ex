defmodule Ordo.Support.PolicyFact do
  @moduledoc "A single structured, accepted shop rule (see CONTEXT.md: Policy fact)."
  use Ecto.Schema

  import Ecto.Changeset

  alias Ordo.Support.Tenant

  schema "policy_facts" do
    field :key, :string
    field :label, :string
    field :value, :string
    field :unit, :string
    field :category, :string
    field :position, :integer, default: 0

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(fact, attrs) do
    fact
    |> cast(attrs, [:key, :label, :value, :unit, :category, :position, :tenant_id])
    |> validate_required([:key, :label, :value, :tenant_id])
  end

  @doc "One-line rendering of a fact, e.g. \"Okno zwrotu: 14 dni\"."
  def to_line(%__MODULE__{} = f) do
    IO.iodata_to_binary([f.label, ": ", f.value, unit_suffix(f.unit)])
  end

  defp unit_suffix(nil), do: ""
  defp unit_suffix(""), do: ""
  defp unit_suffix(unit), do: " " <> unit
end
