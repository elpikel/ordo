defmodule Ordo.Channels.Fetcher do
  @moduledoc """
  Fetches new mail for an email channel. Behaviour with a `Fake` adapter
  (demo/tests) and the real `IMAP` adapter, selected by the `:channel_fetcher`
  config (default IMAP).

  Returns the current server `uidvalidity` and the new messages (each with its UID
  and raw RFC822 bytes). The adapter owns the incremental logic (UID cursor).
  """

  @type result :: %{uidvalidity: integer() | nil, messages: [%{uid: integer(), raw: binary()}]}

  @callback fetch_new(channel :: struct()) :: {:ok, result} | {:error, term()}

  def fetch_new(channel), do: impl().fetch_new(channel)

  defp impl, do: Application.get_env(:ordo, :channel_fetcher, Ordo.Channels.Fetcher.IMAP)
end
