defmodule Ordo.Mailboxes do
  @moduledoc "Tenant mailboxes and their polling cursor."
  import Ecto.Query

  alias Ordo.Repo
  alias Ordo.Support.Mailbox

  # Demo tenants are never polled (their mailboxes have no real credentials).
  def list_active do
    Repo.all(from m in Mailbox, join: t in assoc(m, :tenant), where: m.active == true and t.demo == false)
  end

  def list_for_tenant(tenant_id) do
    Repo.all(from m in Mailbox, where: m.tenant_id == ^tenant_id, order_by: [asc: m.id])
  end

  def get!(id), do: Repo.get!(Mailbox, id)

  def create(attrs), do: %Mailbox{} |> Mailbox.changeset(attrs) |> Repo.insert()

  def update(%Mailbox{} = mailbox, attrs), do: mailbox |> Mailbox.changeset(attrs) |> Repo.update()

  def delete!(id), do: Mailbox |> Repo.get!(id) |> Repo.delete!()

  def set_active(id, active) do
    id |> get!() |> Mailbox.changeset(%{active: active}) |> Repo.update()
  end

  @doc "Persist the polling cursor / last error after a poll."
  def update_cursor(%Mailbox{} = mailbox, attrs) do
    mailbox |> Mailbox.cursor_changeset(attrs) |> Repo.update()
  end
end
