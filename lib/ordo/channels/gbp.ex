defmodule Ordo.Channels.Gbp do
  @moduledoc """
  Google Business Profile reviews channel. Demo tenants use the `Fake` adapter
  (seeded reviews from `Ordo.Demo`); real tenants use `HTTP` (Google API — a
  stub for now). Adapter is picked by the tenant's `demo` flag, like BaseLinker.
  """
  @behaviour Ordo.Channels.Channel

  @impl true
  def fetch(tenant), do: adapter(tenant).fetch(tenant)

  @impl true
  def send_reply(tenant, ticket, body), do: adapter(tenant).send_reply(tenant, ticket, body)

  defp adapter(%{demo: true}), do: Ordo.Channels.Gbp.Fake
  defp adapter(_), do: Ordo.Channels.Gbp.HTTP
end

defmodule Ordo.Channels.Gbp.Fake do
  @moduledoc "Seeded GBP reviews for the demo; publishing a reply is a no-op."
  @behaviour Ordo.Channels.Channel

  @impl true
  def fetch(_tenant), do: Ordo.Demo.reviews()

  @impl true
  def send_reply(_tenant, _ticket, _body), do: :ok
end

defmodule Ordo.Channels.Gbp.HTTP do
  @moduledoc """
  Real Google Business Profile integration (OAuth + `accounts.locations.reviews`
  list / reply). Not implemented yet — the Fake proves the seam first (ADR-0011).
  """
  @behaviour Ordo.Channels.Channel

  @impl true
  def fetch(_tenant), do: []

  @impl true
  def send_reply(_tenant, _ticket, _body), do: {:error, :not_implemented}
end
