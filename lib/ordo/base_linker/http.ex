defmodule Ordo.BaseLinker.HTTP do
  @moduledoc """
  Real BaseLinker client (`connector.php`, `X-BLToken` auth), reads only.

  Lookup precedence (see grilling Q3): an integer order ref hits `getOrders`
  by `order_id`; otherwise `getOrders(filter_email:, date_confirmed_from: -90d)`
  gives a candidate set, and we match the ref or fall back to the most recent.
  A matched order is enriched with packages + courier history, and its status_id
  is named via a per-tenant cached `getOrderStatusList`. Any failure returns nil,
  so the composer escalates rather than the pipeline crashing.

  API response shapes are best-effort against BaseLinker's docs and should be
  verified against a real trial account; parsing is defensive on purpose.
  """
  @behaviour Ordo.BaseLinker

  require Logger

  @endpoint "https://api.baselinker.com/connector.php"
  @window_days 90
  @status_ttl :timer.hours(6)

  @impl true
  def resolve(%{bl_token: token}, order_ref, email) when is_binary(token) do
    with order when is_map(order) <- find_order(token, order_ref, email) do
      enrich(token, order)
    else
      _ -> nil
    end
  rescue
    e ->
      Logger.warning("BaseLinker.HTTP.resolve failed: #{Exception.message(e)}")
      nil
  end

  def resolve(_tenant, _order_ref, _email), do: nil

  # --- Lookup -------------------------------------------------------------

  defp find_order(token, order_ref, email) do
    cond do
      integer_ref?(order_ref) ->
        token
        |> get_orders(%{order_id: String.to_integer(order_ref)})
        |> List.first()

      is_binary(email) and email != "" ->
        orders = get_orders(token, %{filter_email: email, date_confirmed_from: window_from()})
        match_ref(orders, order_ref) || List.last(orders)

      true ->
        nil
    end
  end

  defp match_ref(orders, nil), do: match_ref(orders, "")

  defp match_ref(orders, ref) do
    ref = String.trim(ref)
    Enum.find(orders, &(to_string(&1["order_id"]) == ref))
  end

  defp get_orders(token, params) do
    case call(token, "getOrders", params) do
      {:ok, %{"orders" => orders}} when is_list(orders) -> orders
      _ -> []
    end
  end

  # --- Enrichment ---------------------------------------------------------

  defp enrich(token, order) do
    id = order["order_id"]
    pkg = first_package(token, id)

    %{
      "number" => to_string(id),
      "date" => format_date(order["date_add"]),
      "status" => status_name(token, order["order_status_id"]),
      "semantic_status" => nil,
      "customer_name" => order["delivery_fullname"] || order["invoice_fullname"] || "",
      "customer_email" => order["email"],
      "courier" => pkg && pkg["courier_code"],
      "tracking" => pkg && pkg["courier_package_nr"],
      "courier_history" => courier_history(token, pkg),
      "items" => items(order["products"])
    }
  end

  defp first_package(token, order_id) do
    case call(token, "getOrderPackages", %{order_id: order_id}) do
      {:ok, %{"packages" => [pkg | _]}} -> pkg
      _ -> nil
    end
  end

  defp courier_history(_token, nil), do: []

  defp courier_history(token, %{"package_id" => package_id}) do
    case call(token, "getCourierPackagesStatusHistory", %{package_ids: [package_id]}) do
      {:ok, %{"packages_history" => history}} when is_map(history) ->
        history
        |> Map.values()
        |> List.flatten()
        |> Enum.map(fn r ->
          %{
            "date" => format_datetime(r["tracking_status_date"]),
            "status" => r["courier_status_code"] || track_label(r["tracking_status"])
          }
        end)

      _ ->
        []
    end
  end

  defp courier_history(_token, _pkg), do: []

  # BaseLinker standardized tracking_status codes (partial; refine with real data).
  defp track_label(2), do: "Wysłana"
  defp track_label(5), do: "Dostarczona"
  defp track_label(_), do: "Aktualizacja statusu"

  defp items(products) when is_list(products) do
    Enum.map(products, &%{"name" => &1["name"], "qty" => &1["quantity"]})
  end

  defp items(_), do: []

  # --- Status list (cached per token) -------------------------------------

  defp status_name(_token, nil), do: nil

  defp status_name(token, status_id) do
    Map.get(status_list(token), to_string(status_id))
  end

  defp status_list(token) do
    key = {__MODULE__, :statuses, token}

    case :persistent_term.get(key, nil) do
      {map, at} when is_map(map) ->
        if System.monotonic_time(:millisecond) - at < @status_ttl, do: map, else: fetch_statuses(token, key)

      _ ->
        fetch_statuses(token, key)
    end
  end

  defp fetch_statuses(token, key) do
    map =
      case call(token, "getOrderStatusList", %{}) do
        {:ok, %{"statuses" => statuses}} when is_list(statuses) ->
          # Prefer the customer-facing status name over the internal one.
          Map.new(statuses, &{to_string(&1["id"]), &1["name_for_customer"] || &1["name"]})

        _ ->
          %{}
      end

    :persistent_term.put(key, {map, System.monotonic_time(:millisecond)})
    map
  end

  # --- Transport ----------------------------------------------------------

  defp call(token, method, parameters) do
    opts = Application.get_env(:ordo, :baselinker_req_options, [])

    request =
      [
        url: @endpoint,
        headers: [{"x-bltoken", token}],
        form: [method: method, parameters: Jason.encode!(parameters)],
        receive_timeout: 15_000
      ] ++ opts

    case Req.post(request) do
      {:ok, %{status: 200, body: body}} -> decode(body)
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(body) when is_map(body) do
    case body do
      %{"status" => "ERROR"} = b -> {:error, {:bl, b["error_message"] || b["error_code"]}}
      _ -> {:ok, body}
    end
  end

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> decode(map)
      _ -> {:error, :decode}
    end
  end

  defp decode(_), do: {:error, :decode}

  # --- Helpers ------------------------------------------------------------

  defp integer_ref?(ref), do: is_binary(ref) and Regex.match?(~r/^\d+$/, String.trim(ref))
  defp window_from, do: DateTime.utc_now() |> DateTime.add(-@window_days * 24 * 3600, :second) |> DateTime.to_unix()

  defp format_date(unix) when is_integer(unix) and unix > 0 do
    unix |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()
  end

  defp format_date(other), do: to_string(other)

  defp format_datetime(unix) when is_integer(unix) and unix > 0 do
    unix |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp format_datetime(other), do: to_string(other)
end
