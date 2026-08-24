defmodule Ordo.Mailboxes.PollMailbox do
  @moduledoc """
  Polls one mailbox: fetch new mail, ingest each message, advance the UID cursor.
  Unique per mailbox so a still-running or queued poll never stacks.
  """
  use Oban.Worker,
    queue: :mailbox,
    unique: [keys: [:mailbox_id], states: [:available, :scheduled, :executing, :retryable, :suspended]]

  alias Ordo.Mailboxes
  alias Ordo.Mailboxes.Fetcher
  alias Ordo.Support

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mailbox_id" => id}}) do
    mailbox = Mailboxes.get!(id)

    case Fetcher.fetch_new(mailbox) do
      {:ok, %{uidvalidity: uidvalidity, messages: messages}} ->
        Enum.each(messages, fn %{raw: raw} -> Support.ingest_email(mailbox, raw) end)

        last_uid =
          messages
          |> Enum.map(& &1.uid)
          |> Enum.max(fn -> mailbox.last_uid end)

        Mailboxes.update_cursor(mailbox, %{
          uidvalidity: uidvalidity,
          last_uid: last_uid,
          last_polled_at: DateTime.utc_now(),
          last_error: nil
        })

        :ok

      {:error, reason} ->
        Mailboxes.update_cursor(mailbox, %{
          last_polled_at: DateTime.utc_now(),
          last_error: inspect(reason)
        })

        {:error, reason}
    end
  end
end
