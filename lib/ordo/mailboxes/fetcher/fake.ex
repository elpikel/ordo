defmodule Ordo.Mailboxes.Fetcher.Fake do
  @moduledoc "Fetcher for tests/demo — returns messages from the `:fake_fetch` config."
  @behaviour Ordo.Mailboxes.Fetcher

  @impl true
  def fetch_new(_mailbox) do
    {:ok, %{uidvalidity: 1, messages: Application.get_env(:ordo, :fake_fetch, [])}}
  end
end
