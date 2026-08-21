defmodule Ordo.Support do
  @moduledoc """
  The demo support pipeline: an inbound email becomes a Ticket, gets classified,
  matched to a Focus order, drafted, and (on human approval) answered.

  Processing runs in a background Task and broadcasts on each stage so the panel
  animates the pipeline live. Happy-path only — see docs/failure-modes.md.
  """

  import Ecto.Query

  alias Ordo.{AI, BaseLinker, Repo}
  alias Ordo.Support.{Message, Ticket}

  @topic "inbox"

  # --- Queries ------------------------------------------------------------

  def list_tickets do
    Repo.all(from t in Ticket, order_by: [desc: t.inserted_at], preload: [:messages])
  end

  def get_ticket!(id), do: Repo.get!(Ticket, id) |> Repo.preload(:messages)

  # --- Intake -------------------------------------------------------------

  @doc "Feed the artificial inbox. Returns the created Ticket and kicks off processing."
  def receive_email(attrs) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
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
    Process.sleep(700)
    order = BaseLinker.resolve(class.order_ref, ticket.customer_email)
    ticket = update!(ticket, %{order: order})
    broadcast({:ticket_updated, ticket})

    # 3. Compose draft (OTHER gets no draft — draft policy)
    Process.sleep(700)

    draft =
      if class.category == "OTHER" do
        nil
      else
        AI.compose(%{category: class.category, language: class.language, message: body, order: order})
      end

    status = if draft, do: "draft_ready", else: "needs_human"
    ticket = update!(ticket, %{draft: draft, status: status})
    broadcast({:ticket_updated, ticket})
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
