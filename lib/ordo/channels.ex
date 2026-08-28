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

  # Only email channels are polled here; demo tenants have no real credentials.
  def list_active do
    Repo.all(
      from c in Channel,
        join: t in assoc(c, :tenant),
        where: c.type == "email" and c.active == true and t.demo == false
    )
  end

  # Marks a gbp channel whose refresh token was revoked/expired: polling is
  # paused and the operator is prompted to reconnect. Cleared on a fresh connect.
  @gbp_auth_error "auth"

  @doc "The `last_error` marker for a gbp profile that needs reconnecting."
  def gbp_auth_error, do: @gbp_auth_error

  @doc """
  Google Business Profile channels to poll: active, real (non-demo) tenants that
  have connected a profile (a refresh token in `password`) and whose token still
  works — an auth-failed profile is skipped until the operator reconnects.
  """
  def list_active_reviews do
    Repo.all(
      from c in Channel,
        as: :channel,
        join: t in assoc(c, :tenant),
        as: :tenant,
        where: c.type == "gbp" and c.active == true and t.demo == false and not is_nil(c.password),
        where: is_nil(c.last_error) or c.last_error != @gbp_auth_error
    )
  end

  @doc "The tenant's first Google Business Profile channel, or nil (used by the single-profile demo)."
  def gbp_channel(tenant_id) do
    Repo.one(from c in Channel, where: c.tenant_id == ^tenant_id and c.type == "gbp", order_by: [asc: c.id], limit: 1)
  end

  @doc "All of a tenant's Google Business Profile channels, ordered by id."
  def gbp_channels(tenant_id) do
    Repo.all(from c in Channel, where: c.tenant_id == ^tenant_id and c.type == "gbp", order_by: [asc: c.id])
  end

  @doc """
  Connect (or reconnect) a Google Business Profile. A tenant can hold several,
  one per Google account — like mailboxes. Upserts on the account resource id so
  re-running consent refreshes the token instead of adding a duplicate.
  """
  def upsert_gbp_channel(tenant_id, account, attrs) do
    # A successful (re)connect restores health — clear any prior auth failure.
    attrs = Map.put(attrs, :last_error, nil)

    existing =
      Repo.one(
        from c in Channel,
          as: :channel,
          where: c.tenant_id == ^tenant_id and c.type == "gbp",
          where: fragment("? ->> 'account' = ?", c.config, ^account)
      )

    case existing do
      nil -> create(Map.merge(attrs, %{tenant_id: tenant_id, type: "gbp"}))
      channel -> channel |> Channel.changeset(attrs) |> Repo.update()
    end
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
