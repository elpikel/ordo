defmodule OrdoWeb.AnalyticsController do
  @moduledoc """
  First-party proxy for Plausible Analytics. Serves the tracking script and
  forwards events through our own domain so ad/tracker blockers don't drop them.
  Mirrors the `check_signature` setup.
  """
  use OrdoWeb, :controller

  @plausible_host "plausible.przetargowyprzeglad.pl"
  @site_domain "hireordo.com"
  # Extended Plausible script: auto-tracks outbound links + supports tagged custom
  # events (CSS-class based). `hash` is included so in-page anchor navigation on the
  # single-page landing is tracked.
  @script_url "https://#{@plausible_host}/js/script.hash.outbound-links.tagged-events.js"
  @cache_ttl :timer.hours(1)

  def script(conn, _params) do
    case get_cached_script() do
      {:ok, script} ->
        conn
        |> put_resp_content_type("application/javascript")
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_resp(200, script)

      {:error, _reason} ->
        send_resp(conn, 502, "")
    end
  end

  def event(conn, _params) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    headers = [
      {"user-agent", get_req_header(conn, "user-agent") |> List.first() || ""},
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

  defp get_cached_script do
    case :persistent_term.get({__MODULE__, :script}, nil) do
      {script, cached_at} when is_binary(script) ->
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl do
          {:ok, script}
        else
          fetch_and_cache_script()
        end

      _ ->
        fetch_and_cache_script()
    end
  end

  defp fetch_and_cache_script do
    case Req.get(@script_url, req_options()) do
      {:ok, %{status: 200, body: script}} when is_binary(script) ->
        # Point the script's default endpoint at our proxy domain
        modified_script = String.replace(script, @plausible_host, @site_domain)

        :persistent_term.put(
          {__MODULE__, :script},
          {modified_script, System.monotonic_time(:millisecond)}
        )

        {:ok, modified_script}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
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
