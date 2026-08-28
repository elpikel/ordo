defmodule Ordo.Notifications.NotifyWorker do
  @moduledoc """
  Delivers operator notifications for one ticket off the request/pipeline path.
  Unique per ticket for a short window so a burst of updates can't double-notify.
  """
  use Oban.Worker, queue: :notifications, unique: [keys: [:ticket_id], period: 120]

  alias Ordo.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => id}}), do: Notifications.deliver_new_draft(id)
end
