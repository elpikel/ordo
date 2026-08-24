defmodule Ordo.BaseLinker.Fake do
  @moduledoc "Seeded BaseLinker adapter for the demo tenant and tests."
  @behaviour Ordo.BaseLinker

  @impl true
  def resolve(_tenant, order_ref, email) do
    find_order(order_ref: order_ref || "") || find_order(email: email || "")
  end

  @doc "Resolve a Focus order by order number first, then by customer email."
  def find_order(order_ref: ref) when is_binary(ref) do
    Enum.find(orders(), &(&1["number"] == normalize_ref(ref)))
  end

  def find_order(email: email) when is_binary(email) do
    orders()
    |> Enum.filter(&(String.downcase(&1["customer_email"]) == String.downcase(email)))
    |> List.last()
  end

  def find_order(_), do: nil

  def get_order(ref), do: find_order(order_ref: ref)

  defp orders, do: Ordo.Demo.orders()
  defp normalize_ref(ref), do: ref |> String.trim() |> String.upcase()
end
