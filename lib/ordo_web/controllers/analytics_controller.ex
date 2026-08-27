defmodule OrdoWeb.AnalyticsController do
  @moduledoc """
  First-party proxy for Plausible Analytics events. Forwards events through our
  own domain so ad/tracker blockers don't drop them. The tracking script itself
  is a vendored static file at `priv/static/js/stats.js` (served by Plug.Static),
  so only the live event endpoint needs a proxy action.
  """
  use OrdoWeb, :controller

  @plausible_host "plausible.przetargowyprzeglad.pl"

  def event(conn, _params) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    headers = [
      {"user-agent", conn |> get_req_header("user-agent") |> List.first() || ""},
      {"x-forwarded-for", get_client_ip(conn)},
      {"content-type", "application/json"}
    ]

    opts = [body: body, headers: headers] ++ req_options()

    case Req.post("https://#{@plausible_host}/api/event", opts) do
      {:ok, %{status: status, body: resp_body}} ->
        send_resp(conn, status, resp_body || "")

      {:error, _reason} ->
        send_resp(conn, 502, "")
    end
  end

  # Extra Req options, overridable in tests to stub outbound calls (Req.Test).
  defp req_options, do: Application.get_env(:ordo, :analytics_req_options, [])

  defp get_client_ip(conn) do
    conn
    |> get_req_header("x-forwarded-for")
    |> List.first()
    |> case do
      nil -> conn.remote_ip |> :inet.ntoa() |> to_string()
      forwarded -> forwarded |> String.split(",") |> List.first() |> String.trim()
    end
  end
end
