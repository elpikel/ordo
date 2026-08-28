defmodule Ordo.Channels.ScheduleJob do
  @moduledoc """
  Cron-fired every minute (see config). Fans out one poll job per active channel
  — `PollChannel` per email mailbox, `PollReviews` per connected Google profile —
  doing no I/O itself, so a slow channel never blocks scheduling.
  """
  use Oban.Worker, queue: :channel, max_attempts: 1

  alias Ordo.Channels
  alias Ordo.Channels.PollChannel
  alias Ordo.Channels.PollReviews

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(Channels.list_active(), fn c -> Oban.insert(PollChannel.new(%{channel_id: c.id})) end)
    Enum.each(Channels.list_active_reviews(), fn c -> Oban.insert(PollReviews.new(%{channel_id: c.id})) end)
    :ok
  end
end
