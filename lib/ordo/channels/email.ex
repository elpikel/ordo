defmodule Ordo.Channels.Email do
  @moduledoc """
  The email channel. Incoming mail is fetched by the existing Oban channel
  polling (`Ordo.Channels.PollChannel` + `Ordo.Channels.Fetcher`), so `fetch/1`
  here is a no-op. Outbound send through the shop's own SMTP is deferred (ADR-0003), so
  `send_reply/3` currently just succeeds — the reply is already recorded in the
  ticket thread by `Support.approve_and_send/2`.
  """
  @behaviour Ordo.Channels.Channel

  @impl true
  def fetch(_tenant), do: []

  @impl true
  def send_reply(_tenant, _ticket, _body), do: :ok
end
