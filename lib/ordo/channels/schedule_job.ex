defmodule Ordo.Channels.ScheduleJob do
  @moduledoc """
  Cron-fired every minute (see config). Fans out one PollChannel job per active
  email channel — does no IMAP itself, so a slow channel never blocks scheduling.
  """
  use Oban.Worker, queue: :channel, max_attempts: 1

  alias Ordo.Channels
  alias Ordo.Channels.PollChannel

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(Channels.list_active(), fn c -> Oban.insert(PollChannel.new(%{channel_id: c.id})) end)
    :ok
  end
end
