defmodule Ordo.Channels.Fetcher.Fake do
  @moduledoc "Fetcher for tests/demo — returns messages from the `:fake_fetch` config."
  @behaviour Ordo.Channels.Fetcher

  @impl true
  def fetch_new(_channel) do
    {:ok, %{uidvalidity: 1, messages: Application.get_env(:ordo, :fake_fetch, [])}}
  end
end
