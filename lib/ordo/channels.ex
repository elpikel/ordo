defmodule Ordo.Channels do
  @moduledoc """
  Multi-channel inbox (ADR-0011). A channel is a source of customer messages
  (email, Google Business Profile reviews, …) that Ordo fetches into the one
  ticket stream and replies back out on — a first-class `Ordo.Support.Channel`
  row per source. This context owns channel CRUD and the polling cursor, and
  routes a ticket to its channel type's module (`Ordo.Channels.Channel`).
  """
  import Ecto.Query

  alias Ordo.Channels.Email
  alias Ordo.Channels.Gbp
  alias Ordo.Repo
  alias Ordo.Support.Channel
  alias Ordo.Support.Ticket

  @doc "The channels a tenant can filter the inbox by, ordered by id."
  def list_for_tenant(tenant_id) do
    Repo.all(from c in Channel, where: c.tenant_id == ^tenant_id, order_by: [asc: c.id])
  end

  # Only email channels are polled; demo tenants have no real credentials.
  def list_active do
    Repo.all(
      from c in Channel,
        join: t in assoc(c, :tenant),
        where: c.type == "email" and c.active == true and t.demo == false
    )
  end

  @doc "The tenant's Google Business Profile channel, or nil if the integration isn't set up."
  def gbp_channel(tenant_id) do
    Repo.one(from c in Channel, where: c.tenant_id == ^tenant_id and c.type == "gbp", limit: 1)
  end

  def get!(id), do: Repo.get!(Channel, id)

  def create(attrs), do: %Channel{} |> Channel.changeset(attrs) |> Repo.insert()

  def update(%Channel{} = channel, attrs), do: channel |> Channel.changeset(attrs) |> Repo.update()

  def delete!(id), do: Channel |> Repo.get!(id) |> Repo.delete!()

  def set_active(id, active) do
    id |> get!() |> Channel.changeset(%{active: active}) |> Repo.update()
  end

  @doc "Persist the polling cursor / last error after a poll."
  def update_cursor(%Channel{} = channel, attrs) do
    channel |> Channel.cursor_changeset(attrs) |> Repo.update()
  end

  @doc "The channel module handling a given channel type."
  def module("gbp"), do: Gbp
  def module(_), do: Email

  @doc "Send/publish an approved reply out on the ticket's own channel."
  def send_reply(ticket, tenant, body) do
    module(Ticket.channel_type(ticket)).send_reply(tenant, ticket, body)
  end
end
