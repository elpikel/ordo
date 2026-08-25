defmodule Ordo.Mailboxes.ScheduleJob do
  @moduledoc """
  Cron-fired every minute (see config). Fans out one PollMailbox job per active
  mailbox — does no IMAP itself, so a slow mailbox never blocks scheduling.
  """
  use Oban.Worker, queue: :mailbox, max_attempts: 1

  alias Ordo.Mailboxes
  alias Ordo.Mailboxes.PollMailbox

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(Mailboxes.list_active(), fn m -> Oban.insert(PollMailbox.new(%{mailbox_id: m.id})) end)
    :ok
  end
end
