defmodule Ordo.Support do
  @moduledoc """
  The demo support pipeline: an inbound email becomes a Ticket, gets classified,
  matched to a Focus order, drafted (grounded in the tenant's Policy), and — on
  human approval — answered.

  Processing runs in a background Task and broadcasts on each stage so the panel
  animates the pipeline live. Happy-path only — see docs/failure-modes.md.
  """

  import Ecto.Query

  alias Ordo.{AI, BaseLinker, Demo, Repo}
  alias Ordo.Support.{Message, PolicyFact, Tenant, Ticket}

  @topic "inbox"

  # --- Tenant / seeding ---------------------------------------------------

  @doc """
  Resolve a tenant from a URL param — its slug or numeric id. The demo tenant is
  seeded on demand; any other must already exist (raises → 404).
  """
  def fetch_tenant!(param) do
    cond do
      param == Demo.slug() -> ensure_demo_tenant!()
      Regex.match?(~r/^\d+$/, param) -> Repo.get!(Tenant, param) |> with_policy()
      true -> Repo.get_by!(Tenant, slug: param) |> with_policy()
    end
  end

  @doc "Get the demo tenant, creating it and seeding its Policy on first call."
  def ensure_demo_tenant! do
    case Repo.get_by(Tenant, slug: Demo.slug()) do
      nil ->
        {:ok, tenant} = %Tenant{} |> Tenant.changeset(Demo.tenant_attrs()) |> Repo.insert()
        seed_policy!(tenant)
        with_policy(tenant)

      tenant ->
        {:ok, tenant} = tenant |> Tenant.changeset(Demo.tenant_attrs()) |> Repo.update()
        if policy_count(tenant) == 0, do: seed_policy!(tenant)
        with_policy(tenant)
    end
  end

  defp seed_policy!(tenant) do
    Repo.delete_all(from p in PolicyFact, where: p.tenant_id == ^tenant.id)

    Enum.each(Demo.policy_facts(), fn attrs ->
      %PolicyFact{}
      |> PolicyFact.changeset(Map.put(attrs, :tenant_id, tenant.id))
      |> Repo.insert!()
    end)
  end

  defp policy_count(tenant), do: Repo.aggregate(from(p in PolicyFact, where: p.tenant_id == ^tenant.id), :count)
  defp with_policy(tenant), do: Repo.preload(tenant, :policy_facts, force: true)

  def policy_facts(tenant_id) do
    Repo.all(from p in PolicyFact, where: p.tenant_id == ^tenant_id, order_by: [asc: p.position])
  end

  # --- Queries ------------------------------------------------------------

  def list_tickets(tenant_id) do
    Repo.all(
      from t in Ticket,
        where: t.tenant_id == ^tenant_id,
        order_by: [desc: t.inserted_at],
        preload: [:messages]
    )
  end

  def get_ticket!(id), do: Repo.get!(Ticket, id) |> Repo.preload(:messages)

  # --- Inbox management ---------------------------------------------------

  @doc "Empty the tenant's inbox (Wyczyść skrzynkę)."
  def clear_inbox!(tenant_id) do
    Repo.delete_all(from t in Ticket, where: t.tenant_id == ^tenant_id)
    broadcast(:inbox_cleared)
  end

  @doc "Reset and live-ingest the demo mailbox (Importuj skrzynkę). Streams in."
  def import_demo_mailbox!(tenant) do
    clear_inbox!(tenant.id)

    Task.start(fn ->
      Enum.each(Demo.emails(), fn attrs ->
        receive_email(tenant.id, attrs)
        Process.sleep(200)
      end)
    end)

    :ok
  end

  # --- Intake -------------------------------------------------------------

  @doc "Feed the artificial inbox. Returns the created Ticket and kicks off processing."
  def receive_email(tenant_id, attrs) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: tenant_id,
        customer_name: attrs[:customer_name],
        customer_email: attrs[:customer_email],
        subject: attrs[:subject],
        status: "new"
      })
      |> Repo.insert()

    {:ok, _msg} =
      %Message{}
      |> Message.changeset(%{ticket_id: ticket.id, role: "customer", body: attrs[:body]})
      |> Repo.insert()

    ticket = get_ticket!(ticket.id)
    broadcast({:ticket_created, ticket})

    Task.start(fn -> process(ticket, attrs[:body]) end)
    {:ok, ticket}
  end

  defp process(ticket, body) do
    tenant = Repo.get!(Tenant, ticket.tenant_id)

    # 1. Classify
    Process.sleep(500)
    class = AI.classify(ticket.subject, body)

    ticket =
      update!(ticket, %{
        status: "classified",
        category: class.category,
        language: class.language,
        order_ref: class.order_ref,
        sentiment: class.sentiment
      })

    broadcast({:ticket_updated, ticket})

    # 2. Resolve Focus order from BaseLinker
    Process.sleep(600)
    order = BaseLinker.resolve(tenant, class.order_ref, ticket.customer_email)
    ticket = update!(ticket, %{order: order})
    broadcast({:ticket_updated, ticket})

    # 3. Compose draft, grounded in the full Policy. Even out-of-scope mail gets a
    # draft — the composer escalates ("przekazuję do zespołu") when it can't answer,
    # and a human still approves it in Copilot.
    Process.sleep(600)

    draft =
      AI.compose(%{
        category: class.category,
        language: class.language,
        message: body,
        order: order,
        policy: policy_lines(ticket.tenant_id),
        signature: tenant.signature || "Zespół sklepu"
      })

    ticket = update!(ticket, %{draft: draft, status: "draft_ready"})
    broadcast({:ticket_updated, ticket})
  end

  # The full Policy as one-line facts — small enough to always pass; the LLM
  # picks what's relevant.
  defp policy_lines(tenant_id) do
    tenant_id |> policy_facts() |> Enum.map(&PolicyFact.to_line/1)
  end

  # --- Approval -----------------------------------------------------------

  @doc "Human approves (possibly edited) draft: file the reply and resolve."
  def approve_and_send(%Ticket{} = ticket, body) do
    now = DateTime.utc_now()
    seconds = DateTime.diff(now, ticket.inserted_at)

    {:ok, _msg} =
      %Message{}
      |> Message.changeset(%{ticket_id: ticket.id, role: "ordo", body: body})
      |> Repo.insert()

    ticket =
      update!(ticket, %{
        draft: body,
        status: "answered",
        answered_at: now,
        resolution_seconds: max(seconds, 1)
      })

    ticket = get_ticket!(ticket.id)
    broadcast({:ticket_updated, ticket})
    {:ok, ticket}
  end

  defp update!(ticket, attrs) do
    ticket |> Ticket.changeset(attrs) |> Repo.update!()
  end

  # --- PubSub -------------------------------------------------------------

  def subscribe, do: Phoenix.PubSub.subscribe(Ordo.PubSub, @topic)
  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Ordo.PubSub, @topic, msg)
end
