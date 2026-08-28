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
  alias Ordo.Channels
  alias Ordo.Demo
  alias Ordo.Repo
  alias Ordo.Support.Channel
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

    seed_demo_channels!(tenant)
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

  defp seed_demo_channels!(tenant) do
    Enum.each(Demo.mailboxes(), fn email ->
      if is_nil(Repo.get_by(Channel, tenant_id: tenant.id, email: email)) do
        %Channel{}
        |> Channel.changeset(%{tenant_id: tenant.id, type: "email", email: email, active: true})
        |> Repo.insert!()
      end
    end)

    if is_nil(Channels.gbp_channel(tenant.id)) do
      %Channel{}
      |> Channel.changeset(Map.put(Demo.gbp_channel(), :tenant_id, tenant.id))
      |> Repo.insert!()
    end
  end

  @doc """
  Ensure the demo tenant exists (with its channels, incl. the gbp channel) and
  seed its inbox with tickets + messages, so a fresh deploy shows a populated
  demo without clicking "Import". Idempotent — a no-op once tickets exist.

  Runs the demo pipeline inline (no Task/sleeps/broadcasts): `Ordo.AI` and the
  demo `BaseLinker` are deterministic offline, so this is migration-safe.
  """
  def seed_demo_inbox! do
    seed_demo_inbox!(ensure_demo_tenant!())
  end

  def seed_demo_inbox!(tenant) do
    if Repo.exists?(from t in Ticket, where: t.tenant_id == ^tenant.id) do
      :ok
    else
      by_email =
        Map.new(
          Repo.all(from c in Channel, where: c.tenant_id == ^tenant.id and c.type == "email"),
          &{&1.email, &1.id}
        )

      Enum.each(Demo.emails(), &seed_email_ticket!(tenant, by_email, &1))

      gbp = Channels.gbp_channel(tenant.id)
      Enum.each(Demo.reviews(), &seed_review_ticket!(tenant, gbp, &1))
      :ok
    end
  end

  @doc """
  Repair a demo account whose inbox was seeded before the gbp channel existed:
  ensure the gbp channel, re-home orphaned review tickets (null channel_id) onto
  it, and seed any reviews still missing — so the Google channel is populated.
  Idempotent and safe to run repeatedly.
  """
  def fix_demo_account! do
    fix_demo_account!(ensure_demo_tenant!())
  end

  def fix_demo_account!(tenant) do
    if gbp = Channels.gbp_channel(tenant.id) do
      Repo.update_all(
        from(t in Ticket,
          where: t.tenant_id == ^tenant.id and is_nil(t.channel_id) and not is_nil(fragment("? ->> 'review_id'", t.meta))
        ),
        set: [channel_id: gbp.id]
      )

      Enum.each(Demo.reviews(), &seed_review_ticket!(tenant, gbp, &1))
    end

    :ok
  end

  defp seed_email_ticket!(tenant, by_email, attrs) do
    class = AI.classify(attrs.subject, attrs.body)
    order = BaseLinker.resolve(tenant, class.order_ref, attrs.customer_email)

    draft =
      AI.compose(%{
        category: class.category,
        language: class.language,
        message: attrs.body,
        order: order,
        policy: policy_lines(tenant.id),
        signature: tenant.signature || "Zespół sklepu"
      })

    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: tenant.id,
        channel_id: Map.get(by_email, Demo.mailbox_for(attrs)),
        customer_name: attrs.customer_name,
        customer_email: attrs.customer_email,
        subject: attrs.subject,
        status: "draft_ready",
        category: class.category,
        language: class.language,
        order_ref: class.order_ref,
        sentiment: class.sentiment,
        order: order,
        draft: draft
      })
      |> Repo.insert()

    %Message{}
    |> Message.changeset(%{ticket_id: ticket.id, role: "customer", body: attrs.body})
    |> Repo.insert!()
  end

  defp seed_review_ticket!(tenant, gbp, review) do
    ext_id = "gbp:" <> review.id

    if !message_exists?(ext_id) do
      {category, sentiment} = classify_review(review.rating)
      draft = compose_review_reply(category, review, tenant.signature || "Zespół")

      {:ok, ticket} =
        %Ticket{}
        |> Ticket.changeset(%{
          tenant_id: tenant.id,
          channel_id: gbp && gbp.id,
          customer_name: review.author,
          subject: review_subject(review.text),
          status: "draft_ready",
          category: category,
          sentiment: sentiment,
          language: "pl",
          draft: draft,
          meta: %{
            "rating" => review.rating,
            "author_kind" => review.author_kind,
            "review_id" => review.id,
            "posted" => review.posted
          }
        })
        |> Repo.insert()

      %Message{}
      |> Message.changeset(%{ticket_id: ticket.id, role: "customer", body: review.text, message_id: ext_id})
      |> Repo.insert!()
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

  @doc "Preload a tenant's policy facts (used to ground drafts and render the rules sheet)."
  def with_policy(tenant), do: Repo.preload(tenant, :policy_facts, force: true)

  def policy_facts(tenant_id) do
    Repo.all(from p in PolicyFact, where: p.tenant_id == ^tenant_id, order_by: [asc: p.position])
  end

  @doc "Tickets for a tenant, optionally filtered to one channel (nil = all), paginated via :limit/:offset."
  def list_tickets(tenant_id, channel_id \\ nil, opts \\ []) do
    Ticket
    |> where([t], t.tenant_id == ^tenant_id)
    |> maybe_channel(channel_id)
    |> order_by([t], desc: t.inserted_at)
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> preload(:channel)
    |> Repo.all()
  end

  @doc "Counts for the list header: total tickets and drafts awaiting approval."
  def ticket_stats(tenant_id, channel_id \\ nil) do
    base = Ticket |> where([t], t.tenant_id == ^tenant_id) |> maybe_channel(channel_id)
    %{total: Repo.aggregate(base, :count), drafts: Repo.aggregate(where(base, [t], t.status == "draft_ready"), :count)}
  end

  defp maybe_channel(q, nil), do: q
  defp maybe_channel(q, channel_id), do: where(q, [t], t.channel_id == ^channel_id)
  defp maybe_limit(q, nil), do: q
  defp maybe_limit(q, n), do: limit(q, ^n)
  defp maybe_offset(q, nil), do: q
  defp maybe_offset(q, n), do: offset(q, ^n)

  def get_ticket!(id), do: Ticket |> Repo.get!(id) |> Repo.preload([:messages, :channel])

  @doc "Load a ticket by id with messages, or nil if it doesn't exist."
  def get_ticket(id) do
    case Repo.get(Ticket, id) do
      nil -> nil
      ticket -> Repo.preload(ticket, [:messages, :channel])
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

    by_email =
      Map.new(
        Repo.all(from c in Channel, where: c.tenant_id == ^tenant.id and c.type == "email"),
        &{&1.email, &1.id}
      )

    Task.start(fn ->
      Enum.each(Demo.emails(), fn attrs ->
        channel_id = Map.get(by_email, Demo.mailbox_for(attrs))
        receive_email(tenant.id, Map.put(attrs, :channel_id, channel_id))
        Process.sleep(200)
      end)
    end)

    :ok
  end

  @doc "Live-ingest the demo Google reviews. Streams in, like the mailbox import."
  def import_demo_reviews!(tenant) do
    Task.start(fn ->
      Enum.each(Ordo.Channels.Gbp.fetch(tenant), fn review ->
        receive_review(tenant, review)
        Process.sleep(200)
      end)
    end)

    :ok
  end

  @doc """
  Turn one Google review into a Ticket on a gbp channel, then draft a reply.
  Pass the specific `channel` when polling a profile; the demo/manual path omits
  it and lands on the tenant's first gbp channel.
  """
  def receive_review(tenant, review, channel \\ nil) do
    ext_id = "gbp:" <> review.id

    if message_exists?(ext_id) do
      {:skip, :duplicate}
    else
      gbp_channel = channel || Channels.gbp_channel(tenant.id)

      {:ok, ticket} =
        %Ticket{}
        |> Ticket.changeset(%{
          tenant_id: tenant.id,
          channel_id: gbp_channel && gbp_channel.id,
          customer_name: review.author,
          subject: review_subject(review.text),
          status: "new",
          meta: %{
            "rating" => review.rating,
            "author_kind" => review.author_kind,
            "review_id" => review.id,
            "posted" => review.posted
          }
        })
        |> Repo.insert()

      {:ok, _msg} =
        %Message{}
        |> Message.changeset(%{ticket_id: ticket.id, role: "customer", body: review.text, message_id: ext_id})
        |> Repo.insert()

      ticket = get_ticket!(ticket.id)
      broadcast({:ticket_created, ticket})
      Task.start(fn -> process_review(ticket, review) end)
      {:ok, ticket}
    end
  end

  defp review_subject(text) do
    text = String.trim(text)
    if String.length(text) > 60, do: String.slice(text, 0, 60) <> "…", else: text
  end

  # Reviews skip order lookup: classify by rating, then draft a public reply.
  defp process_review(ticket, review) do
    tenant = Repo.get!(Tenant, ticket.tenant_id)

    Process.sleep(400)
    {category, sentiment} = classify_review(review.rating)
    ticket = update!(ticket, %{status: "classified", category: category, sentiment: sentiment, language: "pl"})
    broadcast({:ticket_updated, ticket})

    Process.sleep(500)
    draft = compose_review_reply(category, review, tenant.signature || "Zespół")
    ticket = update!(ticket, %{draft: draft, status: "draft_ready"})
    broadcast({:ticket_updated, ticket})
    Ordo.Notifications.enqueue(ticket)
  end

  defp classify_review(rating) when rating >= 5, do: {"REVIEW_POSITIVE", "positive"}
  defp classify_review(rating) when rating <= 2, do: {"REVIEW_NEGATIVE", "angry"}
  defp classify_review(_rating), do: {"REVIEW_MIXED", "neutral"}

  defp compose_review_reply("REVIEW_POSITIVE", review, signature) do
    "#{first_name(review.author)}, dziękujemy za tak miłe słowa — takie opinie dają nam najwięcej energii do działania! " <>
      "Cieszymy się, że wszystko się spodobało, i zapraszamy ponownie.\n\nPozdrawiamy,\n#{signature}"
  end

  defp compose_review_reply("REVIEW_NEGATIVE", review, signature) do
    "#{first_name(review.author)}, bardzo nam przykro z powodu tej sytuacji i przepraszamy za niedogodności. " <>
      "Chcemy to naprawić — napiszemy do Państwa bezpośrednio, żeby wyjaśnić sprawę i zaproponować rozwiązanie.\n\nPozdrawiamy,\n#{signature}"
  end

  defp compose_review_reply(_mixed, review, signature) do
    "#{first_name(review.author)}, dziękujemy za opinię i szczery feedback! Cieszymy się, że produkty smakują, " <>
      "a uwagę o dostawie bierzemy sobie do serca i już nad tym pracujemy.\n\nPozdrawiamy,\n#{signature}"
  end

  defp first_name(author) do
    case String.split(author, " ", parts: 2) do
      [first | _] -> first
      _ -> author
    end
  end

  @doc "Feed the artificial inbox. Returns the created Ticket and kicks off processing."
  def receive_email(tenant_id, attrs) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: tenant_id,
        channel_id: attrs[:channel_id],
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
    Ordo.Notifications.enqueue(ticket)
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

    # Publish/send the reply out on the ticket's own channel (email SMTP deferred,
    # GBP publishes to Google — Fake no-ops in demo).
    tenant = Repo.get!(Tenant, ticket.tenant_id)
    Channels.send_reply(ticket, tenant, body)

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

  # Keep :channel loaded so broadcast tickets rendered straight into the inbox
  # stream can still resolve their channel type (no query when already loaded).
  defp update!(ticket, attrs) do
    ticket |> Ticket.changeset(attrs) |> Repo.update!() |> Repo.preload(:channel)
  end

  @doc """
  Turn one raw RFC822 email (from a mailbox poll) into a Ticket. INBOX-only, so
  no loop guard (ADR-0008): drop machine mail, dedup by Message-ID, then thread
  by References or create a new Ticket. Returns {:ok, ticket} or {:skip, reason}.
  """
  def ingest_email(%Channel{} = channel, raw) do
    case parse_email(raw) do
      nil ->
        {:skip, :unparseable}

      email ->
        cond do
          machine_mail?(email) -> {:skip, :machine}
          from_self?(channel, email) -> {:skip, :self}
          email.message_id && message_exists?(email.message_id) -> {:skip, :duplicate}
          true -> do_ingest(channel, email)
        end
    end
  end

  defp do_ingest(channel, email) do
    case find_thread(email) do
      nil -> create_ticket_from_email(channel, email)
      ticket -> append_to_thread(ticket, email)
    end
  end

  defp create_ticket_from_email(channel, email) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: channel.tenant_id,
        channel_id: channel.id,
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

  defp from_self?(channel, email) do
    is_binary(email.from_email) and is_binary(channel.email) and
      String.downcase(email.from_email) == String.downcase(channel.email)
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
