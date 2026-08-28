defmodule Ordo.Channels.PollReviews do
  @moduledoc """
  Polls one connected Google Business Profile: fetch its reviews and ingest each
  as a ticket (dedup by `gbp:<review_id>`). Unique per channel so a still-running
  or queued poll never stacks — the GBP twin of `PollChannel`.
  """
  use Oban.Worker,
    queue: :channel,
    unique: [keys: [:channel_id], states: [:available, :scheduled, :executing, :retryable, :suspended]]

  alias Ordo.Channels
  alias Ordo.Channels.Gbp
  alias Ordo.Repo
  alias Ordo.Support

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel_id" => id}}) do
    channel = id |> Channels.get!() |> Repo.preload(:tenant)

    case Gbp.fetch_channel(channel) do
      {:ok, reviews} ->
        Enum.each(reviews, &Support.receive_review(channel.tenant, &1, channel))
        stamp(channel, nil)
        :ok

      # Revoked/expired token: pause polling and flag for reconnect (not retryable).
      {:error, :auth} ->
        stamp(channel, Channels.gbp_auth_error())
        :ok

      # Transient (network, 5xx): record it and let Oban retry the job.
      {:error, reason} ->
        stamp(channel, inspect(reason))
        {:error, reason}
    end
  end

  defp stamp(channel, last_error) do
    Channels.update_cursor(channel, %{last_polled_at: DateTime.utc_now(), last_error: last_error})
  end
end
