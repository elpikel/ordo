defmodule Mix.Tasks.Ordo.RefreshAnalytics do
  @shortdoc "Re-vendor the Plausible tracking script into priv/static/js"
  @moduledoc """
  Download the current Plausible tracking script and write it to
  `priv/static/js/stats.js`, the first-party static asset served by Plug.Static.

      mix ordo.refresh_analytics

  Run this when you want to pick up Plausible's script updates, then commit the
  resulting diff so the change is reviewable. The event endpoint stays a live
  proxy in OrdoWeb.AnalyticsController; only the script is vendored here.
  """
  use Mix.Task

  # Extended build: hash routing + outbound-link + tagged-event tracking.
  @source_url "https://plausible.przetargowyprzeglad.pl/js/script.hash.outbound-links.tagged-events.js"
  @dest "priv/static/js/stats.js"

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:req)

    case Req.get(@source_url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        File.write!(@dest, body)
        Mix.shell().info("Wrote #{byte_size(body)} bytes to #{@dest}")

      {:ok, %{status: status}} ->
        Mix.raise("Unexpected status #{status} fetching #{@source_url}")

      {:error, reason} ->
        Mix.raise("Failed to fetch #{@source_url}: #{inspect(reason)}")
    end
  end
end
