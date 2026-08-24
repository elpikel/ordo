defmodule Ordo.BaseLinker do
  @moduledoc """
  BaseLinker order lookup, per-tenant. The demo tenant uses the seeded `Fake`
  adapter; every other tenant uses the real `HTTP` client with its own token.

  Reads only for now (see ADR-0001: writes are deferred to approval). Adapters
  translate BaseLinker responses into a stable Ordo order map so the pipeline,
  composer, and panel never change shape.
  """

  @doc "Resolve the Focus order for a Ticket. Returns an order map or nil."
  @callback resolve(tenant :: struct(), order_ref :: String.t() | nil, email :: String.t() | nil) ::
              map() | nil

  def resolve(tenant, order_ref, email) do
    adapter(tenant).resolve(tenant, order_ref, email)
  end

  defp adapter(%{demo: true}), do: Ordo.BaseLinker.Fake
  defp adapter(_), do: Ordo.BaseLinker.HTTP
end
