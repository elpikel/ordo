defmodule Ordo.Notifications do
  @moduledoc """
  Operator notifications: when a ticket reaches `draft_ready`, ping the shop's
  operators with the customer's original message and Ordo's proposed reply, so
  they can approve out-of-band — a one-click button in email, or an "OK" reply on
  WhatsApp. Real (non-demo) tenants only; demo drafts are silent.

  `enqueue/1` schedules the work on Oban; the `NotifyWorker` calls
  `deliver_new_draft/1`. Sending is best-effort — a failed send is logged, not
  retried, so a flaky provider never re-spams the whole team on retry.
  """
  use OrdoWeb, :verified_routes
  use Gettext, backend: OrdoWeb.Gettext

  import Ecto.Query

  alias Ordo.Notifications.NotifyWorker
  alias Ordo.Notifications.OperatorEmail
  alias Ordo.Notifications.Token
  alias Ordo.Notifications.WhatsApp
  alias Ordo.Repo
  alias Ordo.Support
  alias Ordo.Support.Tenant
  alias Ordo.Support.Ticket

  require Logger

  @doc "Schedule operator notifications for a ticket that just became `draft_ready`."
  def enqueue(%Ticket{id: id}), do: Oban.insert(NotifyWorker.new(%{"ticket_id" => id}))

  @doc """
  Notify the tenant's operators about a ready draft. Loads the ticket fresh and
  no-ops unless it's still `draft_ready` on a real tenant. Always returns `:ok`.
  """
  def deliver_new_draft(ticket_id) when is_integer(ticket_id) do
    ticket = ticket_id |> Support.get_ticket!() |> Repo.preload(tenant: :users)

    if notifiable?(ticket) do
      ctx = context(ticket)
      Enum.each(ticket.tenant.users, &send_email(&1, ctx))
      send_whatsapp(ticket.tenant, ctx)
    end

    :ok
  end

  @doc "The signed one-click approval URL for a ticket (also used by the email button)."
  def approve_url(ticket_id), do: url(~p"/n/#{Token.sign(ticket_id)}")

  # Opt-in only: the shop must have switched notifications on in settings, and the
  # demo tenant never emails/messages for real.
  defp notifiable?(%Ticket{status: "draft_ready", tenant: %{demo: false, notify_enabled: true}}), do: true
  defp notifiable?(_), do: false

  defp context(ticket) do
    %{
      ticket_id: ticket.id,
      # The ticket id doubles as the reply code: "OK 4821" targets exactly this
      # draft, so a WhatsApp "OK" is never ambiguous when several are pending.
      code: ticket.id,
      customer_name: ticket.customer_name || gettext_customer(),
      subject: ticket.subject || "",
      original: original_message(ticket),
      draft: ticket.draft || "",
      approve_url: approve_url(ticket.id),
      inbox_url: url(~p"/inbox/#{ticket.id}")
    }
  end

  defp original_message(%Ticket{messages: messages}) when is_list(messages) do
    case Enum.find(messages, &(&1.role == "customer")) do
      %{body: body} -> body
      _ -> ""
    end
  end

  defp original_message(_), do: ""

  defp send_email(%{email: email}, ctx) when is_binary(email) do
    case OperatorEmail.deliver_new_draft(email, ctx) do
      {:ok, _} -> :ok
      other -> Logger.warning("Notify email to #{email} failed: #{inspect(other)}")
    end
  end

  defp send_email(_, _), do: :ok

  defp send_whatsapp(%{notify_whatsapp: number} = tenant, ctx) when is_binary(number) and number != "" do
    case WhatsApp.send_message(tenant, number, whatsapp_message(ctx)) do
      :ok -> :ok
      other -> Logger.warning("Notify WhatsApp to #{number} failed: #{inspect(other)}")
    end
  end

  defp send_whatsapp(_, _), do: :ok

  # A business-initiated ping outside the 24h window must use a pre-approved
  # template; in-session (or in tests) we send text. Both carry the full original
  # message and proposed reply — the operator needs them to actually decide.
  # Template body placeholders, in order: customer name, original message,
  # proposed reply, reply code. Template *values* can't contain newlines, so the
  # message/reply are whitespace-collapsed (the text variant keeps its newlines).
  defp whatsapp_message(ctx) do
    case WhatsApp.CloudAPI.template() do
      {name, lang} ->
        {:template, name, lang, [ctx.customer_name, wa_param(ctx.original), wa_param(ctx.draft), ctx.code]}

      nil ->
        {:text, whatsapp_text(ctx)}
    end
  end

  # WhatsApp forbids newlines/tabs/runs of spaces in template values; collapse and
  # cap so a long draft still fits (the confirm-in-inbox link has the full text).
  @wa_param_limit 700
  defp wa_param(text) do
    text |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim() |> truncate(@wa_param_limit)
  end

  defp truncate(s, n), do: if(String.length(s) > n, do: String.slice(s, 0, n - 1) <> "…", else: s)

  # Approve by replying "OK <code>" (or plain "OK" for the most recent);
  # the inbox link is for editing instead.
  defp whatsapp_text(ctx) do
    gettext(
      """
      🔔 New message from %{name}:

      "%{original}"

      Ordo's proposed reply:

      %{draft}

      Reply OK %{code} to send it, or edit in the inbox: %{inbox_url}
      """,
      name: ctx.customer_name,
      original: ctx.original,
      draft: ctx.draft,
      code: ctx.code,
      inbox_url: ctx.inbox_url
    )
  end

  defp gettext_customer, do: gettext("customer")

  @doc """
  Find the tenant's pending ticket a WhatsApp sender is approving. Prefers an
  explicit ticket id in the text (e.g. "OK 4821"); otherwise the most recent
  `draft_ready` ticket for the tenant whose `notify_whatsapp` matches the sender.
  Returns a `Ticket` or nil.
  """
  def pending_ticket_for(sender_number, text) do
    with %{} = tenant <- tenant_for_number(sender_number) do
      case explicit_ticket_id(text) do
        nil -> latest_draft(tenant.id)
        id -> Repo.one(from t in draft_scope(tenant.id), where: t.id == ^id)
      end
    end
  end

  defp tenant_for_number(sender) do
    digits = String.replace(sender || "", ~r/\D/, "")

    if digits == "" do
      nil
    else
      Repo.one(
        from t in Tenant,
          where: fragment("regexp_replace(?, '[^0-9]', '', 'g')", t.notify_whatsapp) == ^digits,
          limit: 1
      )
    end
  end

  defp latest_draft(tenant_id) do
    Repo.one(from t in draft_scope(tenant_id), order_by: [desc: t.inserted_at], limit: 1)
  end

  defp draft_scope(tenant_id) do
    from t in Ticket, where: t.tenant_id == ^tenant_id and t.status == "draft_ready"
  end

  defp explicit_ticket_id(text) do
    case Regex.run(~r/\b(\d{2,})\b/, text || "") do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end
end
