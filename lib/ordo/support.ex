defmodule Ordo.Support do
  @moduledoc """
  The demo support pipeline: an inbound email becomes a Ticket, gets classified,
  matched to a Focus order, drafted (grounded in the tenant's Policy), and — on
  human approval — answered.

  Processing runs in a background Task and broadcasts on each stage so the panel
  animates the pipeline live. Happy-path only — see docs/failure-modes.md.
  """

  import Ecto.Query

  alias Ordo.Accounts.User
  alias Ordo.AI
  alias Ordo.BaseLinker
  alias Ordo.Demo
  alias Ordo.Repo
  alias Ordo.Support.Mailbox
  alias Ordo.Support.Message
  alias Ordo.Support.PolicyFact
  alias Ordo.Support.Tenant
  alias Ordo.Support.Ticket

  @topic "inbox"

  @doc """
  Resolve a tenant from a URL param — its slug or numeric id. The demo tenant is
  seeded on demand; any other must already exist (raises → 404).
  """
  def fetch_tenant!(param) do
    cond do
      param == Demo.slug() -> ensure_demo_tenant!()
      Regex.match?(~r/^\d+$/, param) -> Tenant |> Repo.get!(param) |> with_policy()
      true -> Tenant |> Repo.get_by!(slug: param) |> with_policy()
    end
  end

  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant |> Tenant.changeset(attrs) |> Repo.update()
  end

  @doc "Get the demo tenant, creating it and seeding its Policy on first call."
  def ensure_demo_tenant! do
    tenant =
      case Repo.get_by(Tenant, slug: Demo.slug()) do
        nil ->
          {:ok, t} = %Tenant{} |> Tenant.changeset(Demo.tenant_attrs()) |> Repo.insert()
          seed_policy!(t)
          t

        t ->
          {:ok, t} = t |> Tenant.changeset(Demo.tenant_attrs()) |> Repo.update()
          if policy_count(t) == 0, do: seed_policy!(t)
          t
      end

    seed_demo_mailboxes!(tenant)
    seed_demo_user!(tenant)
    with_policy(tenant)
  end

  @doc "The activated demo user (seeded on demand), used by the public /demo login."
  def demo_user, do: Repo.get_by(User, email: Demo.user_email())

  defp seed_demo_user!(tenant) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    case Repo.get_by(User, email: Demo.user_email()) do
      nil ->
        %User{}
        |> User.invitation_changeset(%{email: Demo.user_email(), tenant_id: tenant.id})
        |> Ecto.Changeset.put_change(:confirmed_at, now)
        |> User.password_changeset(%{password: Demo.password()})
        |> Repo.insert!()

      %User{hashed_password: nil} = user ->
        user |> User.password_changeset(%{password: Demo.password()}) |> Repo.update!()

      user ->
        user
    end
  end

  defp seed_demo_mailboxes!(tenant) do
    Enum.each(Demo.mailboxes(), fn email ->
      if is_nil(Repo.get_by(Mailbox, tenant_id: tenant.id, email: email)) do
        %Mailbox{} |> Mailbox.changeset(%{tenant_id: tenant.id, email: email, active: true}) |> Repo.insert!()
      end
    end)
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

  @doc "Preload a tenant's policy facts (used to ground drafts and render the rules sheet)."
  def with_policy(tenant), do: Repo.preload(tenant, :policy_facts, force: true)

  def policy_facts(tenant_id) do
    Repo.all(from p in PolicyFact, where: p.tenant_id == ^tenant_id, order_by: [asc: p.position])
  end

  @doc "Tickets for a tenant, filtered to one mailbox (nil = all), paginated via :limit/:offset."
  def list_tickets(tenant_id, mailbox_id \\ nil, opts \\ []) do
    Ticket
    |> where([t], t.tenant_id == ^tenant_id)
    |> maybe_mailbox(mailbox_id)
    |> order_by([t], desc: t.inserted_at)
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> Repo.all()
  end

  @doc "Counts for the list header: total tickets and drafts awaiting approval."
  def ticket_stats(tenant_id, mailbox_id \\ nil) do
    base = Ticket |> where([t], t.tenant_id == ^tenant_id) |> maybe_mailbox(mailbox_id)
    %{total: Repo.aggregate(base, :count), drafts: Repo.aggregate(where(base, [t], t.status == "draft_ready"), :count)}
  end

  defp maybe_mailbox(q, nil), do: q
  defp maybe_mailbox(q, mailbox_id), do: where(q, [t], t.mailbox_id == ^mailbox_id)
  defp maybe_limit(q, nil), do: q
  defp maybe_limit(q, n), do: limit(q, ^n)
  defp maybe_offset(q, nil), do: q
  defp maybe_offset(q, n), do: offset(q, ^n)

  def get_ticket!(id), do: Ticket |> Repo.get!(id) |> Repo.preload(:messages)

  @doc "Load a ticket by id with messages, or nil if it doesn't exist."
  def get_ticket(id) do
    case Repo.get(Ticket, id) do
      nil -> nil
      ticket -> Repo.preload(ticket, :messages)
    end
  end

  @doc "Empty the tenant's inbox (Wyczyść skrzynkę)."
  def clear_inbox!(tenant_id) do
    Repo.delete_all(from t in Ticket, where: t.tenant_id == ^tenant_id)
    broadcast(:inbox_cleared)
  end

  @doc "Reset and live-ingest the demo mailbox (Importuj skrzynkę). Streams in."
  def import_demo_mailbox!(tenant) do
    clear_inbox!(tenant.id)
    by_email = Map.new(Repo.all(from m in Mailbox, where: m.tenant_id == ^tenant.id), &{&1.email, &1.id})

    Task.start(fn ->
      Enum.each(Demo.emails(), fn attrs ->
        mailbox_id = Map.get(by_email, Demo.mailbox_for(attrs))
        receive_email(tenant.id, Map.put(attrs, :mailbox_id, mailbox_id))
        Process.sleep(200)
      end)
    end)

    :ok
  end

  @doc "Feed the artificial inbox. Returns the created Ticket and kicks off processing."
  def receive_email(tenant_id, attrs) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: tenant_id,
        mailbox_id: attrs[:mailbox_id],
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

  @doc "Human takes the ticket over — clears Ordo's draft so they write their own."
  def take_over(%Ticket{} = ticket) do
    ticket = ticket |> update!(%{draft: ""}) |> then(&get_ticket!(&1.id))
    broadcast({:ticket_updated, ticket})
    {:ok, ticket}
  end

  defp update!(ticket, attrs) do
    ticket |> Ticket.changeset(attrs) |> Repo.update!()
  end

  @doc """
  Turn one raw RFC822 email (from a mailbox poll) into a Ticket. INBOX-only, so
  no loop guard (ADR-0008): drop machine mail, dedup by Message-ID, then thread
  by References or create a new Ticket. Returns {:ok, ticket} or {:skip, reason}.
  """
  def ingest_email(%Mailbox{} = mailbox, raw) do
    case parse_email(raw) do
      nil ->
        {:skip, :unparseable}

      email ->
        cond do
          machine_mail?(email) -> {:skip, :machine}
          from_self?(mailbox, email) -> {:skip, :self}
          email.message_id && message_exists?(email.message_id) -> {:skip, :duplicate}
          true -> do_ingest(mailbox, email)
        end
    end
  end

  defp do_ingest(mailbox, email) do
    case find_thread(email) do
      nil -> create_ticket_from_email(mailbox, email)
      ticket -> append_to_thread(ticket, email)
    end
  end

  defp create_ticket_from_email(mailbox, email) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: mailbox.tenant_id,
        mailbox_id: mailbox.id,
        customer_name: email.from_name,
        customer_email: email.from_email,
        subject: email.subject,
        status: "new"
      })
      |> Repo.insert()

    insert_customer_message(ticket.id, email)
    ticket = get_ticket!(ticket.id)
    broadcast({:ticket_created, ticket})
    Task.start(fn -> process(ticket, email.body) end)
    {:ok, ticket}
  end

  defp append_to_thread(ticket, email) do
    insert_customer_message(ticket.id, email)
    ticket = ticket |> update!(%{status: "new"}) |> get_reloaded()
    broadcast({:ticket_updated, ticket})
    Task.start(fn -> process(ticket, email.body) end)
    {:ok, ticket}
  end

  defp get_reloaded(ticket), do: get_ticket!(ticket.id)

  defp insert_customer_message(ticket_id, email) do
    %Message{}
    |> Message.changeset(%{
      ticket_id: ticket_id,
      role: "customer",
      body: email.body,
      message_id: email.message_id,
      in_reply_to: email.in_reply_to
    })
    |> Repo.insert()
  end

  defp find_thread(email) do
    ids = [email.in_reply_to | email.references] |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      nil
    else
      case Repo.one(from m in Message, where: m.message_id in ^ids, order_by: [desc: m.inserted_at], limit: 1) do
        nil -> nil
        msg -> Repo.get(Ticket, msg.ticket_id)
      end
    end
  end

  defp message_exists?(message_id), do: Repo.exists?(from m in Message, where: m.message_id == ^message_id)

  defp machine_mail?(email) do
    email.auto_submitted not in [nil, "no"] or
      email.return_path == "<>" or
      not is_nil(email.list_id) or
      not is_nil(email.list_unsub)
  end

  defp from_self?(mailbox, email) do
    is_binary(email.from_email) and is_binary(mailbox.email) and
      String.downcase(email.from_email) == String.downcase(mailbox.email)
  end

  defp parse_email(raw) do
    msg = Mail.parse(raw)
    {name, addr} = parse_from(Mail.get_from(msg))

    %{
      from_name: name,
      from_email: addr,
      subject: Mail.get_subject(msg) || "(bez tematu)",
      body: text_body(msg),
      message_id: header_id(msg, "message-id"),
      in_reply_to: header_id(msg, "in-reply-to"),
      references: parse_references(Mail.Message.get_header(msg, "references")),
      auto_submitted: Mail.Message.get_header(msg, "auto-submitted"),
      return_path: Mail.Message.get_header(msg, "return-path"),
      list_id: Mail.Message.get_header(msg, "list-id"),
      list_unsub: Mail.Message.get_header(msg, "list-unsubscribe")
    }
  rescue
    _ -> nil
  end

  defp text_body(msg) do
    case Mail.get_text(msg) do
      %Mail.Message{body: body} when is_binary(body) -> String.trim(body)
      _ -> msg.body |> to_string() |> String.trim()
    end
  end

  defp parse_from({name, addr}), do: {presence(name), addr}

  defp parse_from(from) when is_binary(from) do
    case Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, from) do
      [_, name, addr] -> {presence(name), addr}
      _ -> {nil, String.trim(from)}
    end
  end

  defp parse_from([first | _]), do: parse_from(first)
  defp parse_from(_), do: {nil, nil}

  defp header_id(msg, key), do: msg |> Mail.Message.get_header(key) |> strip_brackets()

  defp strip_brackets(v) when is_binary(v),
    do: v |> String.trim() |> String.trim_leading("<") |> String.trim_trailing(">")

  defp strip_brackets(_), do: nil

  defp parse_references(refs) when is_binary(refs),
    do: ~r/<([^>]+)>/ |> Regex.scan(refs) |> Enum.map(fn [_, id] -> id end)

  defp parse_references(_), do: []

  defp presence(nil), do: nil
  defp presence(v) when is_binary(v), do: (String.trim(v) == "" && nil) || String.trim(v)
  defp presence(_), do: nil

  def subscribe, do: Phoenix.PubSub.subscribe(Ordo.PubSub, @topic)
  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Ordo.PubSub, @topic, msg)
end
