defmodule Ordo.Mailboxes.Fetcher do
  @moduledoc """
  Fetches new mail for a mailbox. Behaviour with a `Fake` adapter (demo/tests) and
  the real `IMAP` adapter, selected by the `:mailbox_fetcher` config (default IMAP).

  Returns the current server `uidvalidity` and the new messages (each with its UID
  and raw RFC822 bytes). The adapter owns the incremental logic (UID cursor).
  """

  @type result :: %{uidvalidity: integer() | nil, messages: [%{uid: integer(), raw: binary()}]}

  @callback fetch_new(mailbox :: struct()) :: {:ok, result} | {:error, term()}

  def fetch_new(mailbox), do: impl().fetch_new(mailbox)

  defp impl, do: Application.get_env(:ordo, :mailbox_fetcher, Ordo.Mailboxes.Fetcher.IMAP)
end
