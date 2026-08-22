defmodule Ordo.BaseLinker do
  @moduledoc """
  Demo BaseLinker adapter: returns seeded orders instead of calling the real API.

  This is the seam — the real trial-API client slots in behind the same
  `find_order/1` / `get_order/1` shape later, without touching the pipeline.
  Orders are string-keyed maps so they round-trip cleanly through the tickets
  `:map` (jsonb) column.
  """

  defp orders, do: Ordo.Demo.orders()

  @doc "Resolve a Focus order by order number first, then by customer email."
  def find_order(order_ref: ref) when is_binary(ref) do
    Enum.find(orders(), &(&1["number"] == normalize_ref(ref)))
  end

  def find_order(email: email) when is_binary(email) do
    Enum.filter(orders(), &(String.downcase(&1["customer_email"]) == String.downcase(email)))
    |> List.last()
  end

  def find_order(_), do: nil

  @doc "Resolve by ref, falling back to email — mirrors CONTEXT.md precedence."
  def resolve(order_ref, email) do
    find_order(order_ref: order_ref || "") || find_order(email: email || "")
  end

  def get_order(ref), do: find_order(order_ref: ref)

  defp normalize_ref(ref), do: ref |> String.trim() |> String.upcase()
end
