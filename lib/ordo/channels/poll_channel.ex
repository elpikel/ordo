defmodule Ordo.Channels.PollChannel do
  @moduledoc """
  Polls one email channel: fetch new mail, ingest each message, advance the UID
  cursor. Unique per channel so a still-running or queued poll never stacks.
  """
  use Oban.Worker,
    queue: :channel,
    unique: [keys: [:channel_id], states: [:available, :scheduled, :executing, :retryable, :suspended]]

  alias Ordo.Channels
  alias Ordo.Channels.Fetcher
  alias Ordo.Support

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel_id" => id}}) do
    channel = Channels.get!(id)

    case Fetcher.fetch_new(channel) do
      {:ok, %{uidvalidity: uidvalidity, messages: messages}} ->
        Enum.each(messages, fn %{raw: raw} -> Support.ingest_email(channel, raw) end)

        last_uid =
          messages
          |> Enum.map(& &1.uid)
          |> Enum.max(fn -> channel.last_uid end)

        Channels.update_cursor(channel, %{
          uidvalidity: uidvalidity,
          last_uid: last_uid,
          last_polled_at: DateTime.utc_now(),
          last_error: nil
        })

        :ok

      {:error, reason} ->
        Channels.update_cursor(channel, %{
          last_polled_at: DateTime.utc_now(),
          last_error: inspect(reason)
        })

        {:error, reason}
    end
  end
end
