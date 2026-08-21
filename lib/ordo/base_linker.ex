defmodule Ordo.BaseLinker do
  @moduledoc """
  Demo BaseLinker adapter: returns seeded orders instead of calling the real API.

  This is the seam — the real trial-API client slots in behind the same
  `find_order/1` / `get_order/1` shape later, without touching the pipeline.
  Orders are string-keyed maps so they round-trip cleanly through the tickets
  `:map` (jsonb) column.
  """

  @orders [
    %{
      "number" => "ZAM-88317",
      "date" => "2026-08-12",
      "status" => "Wysłane",
      "semantic_status" => "dispatched",
      "customer_name" => "Anna Kowalska",
      "customer_email" => "anna.kowalska@gmail.com",
      "courier" => "InPost",
      "tracking" => "620441882",
      "courier_history" => [
        %{"date" => "2026-08-12 09:14", "status" => "Nadano przesyłkę"},
        %{"date" => "2026-08-13 06:02", "status" => "Przyjęto w sortowni"},
        %{"date" => "2026-08-13 11:20", "status" => "Wydano do doręczenia"}
      ],
      "items" => [%{"name" => "Buty trekkingowe Alpine 42", "qty" => 1}]
    },
    %{
      "number" => "ZAM-90042",
      "date" => "2026-08-18",
      "status" => "W realizacji",
      "semantic_status" => "processing",
      "customer_name" => "Marek Zieliński",
      "customer_email" => "m.zielinski@wp.pl",
      "courier" => nil,
      "tracking" => nil,
      "courier_history" => [],
      "items" => [%{"name" => "Kurtka puchowa Nord L", "qty" => 1}]
    }
  ]

  @doc "Resolve a Focus order by order number first, then by customer email."
  def find_order(order_ref: ref) when is_binary(ref) do
    Enum.find(@orders, &(&1["number"] == normalize_ref(ref)))
  end

  def find_order(email: email) when is_binary(email) do
    Enum.find(@orders, &(String.downcase(&1["customer_email"]) == String.downcase(email)))
  end

  def find_order(_), do: nil

  @doc "Resolve by ref, falling back to email — mirrors CONTEXT.md precedence."
  def resolve(order_ref, email) do
    find_order(order_ref: order_ref || "") || find_order(email: email || "")
  end

  def get_order(ref), do: find_order(order_ref: ref)

  defp normalize_ref(ref), do: ref |> String.trim() |> String.upcase()
end
