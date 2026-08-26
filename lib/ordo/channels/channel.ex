defmodule Ordo.Channels.Channel do
  @moduledoc """
  Behaviour for an inbox channel. `fetch/1` pulls new incoming items for a
  tenant; `send_reply/3` publishes an approved reply back out. Adapters are
  chosen per tenant (`Fake` for demo tenants, real `HTTP` otherwise), mirroring
  the BaseLinker and email Fetcher patterns.
  """

  @doc "Normalized incoming items for the tenant (channel-specific maps)."
  @callback fetch(tenant :: struct()) :: [map()]

  @doc "Publish/send an approved reply for a ticket."
  @callback send_reply(tenant :: struct(), ticket :: struct(), body :: String.t()) ::
              :ok | {:error, term()}
end
