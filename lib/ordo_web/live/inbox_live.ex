defmodule OrdoWeb.InboxLive do
  @moduledoc "Support panel: three-column inbox with rules slide-over and BaseLinker receipt."
  use OrdoWeb, :live_view

  alias Ordo.Channels
  alias Ordo.Support
  alias Ordo.Support.Ticket

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Support.subscribe()

    tenant = Support.with_policy(socket.assigns.current_scope.tenant)

    {:ok,
     socket
     |> assign(
       tenant: tenant,
       channels: Channels.list_for_tenant(tenant.id),
       channel_id: nil,
       selected_id: nil,
       ticket: nil,
       page: 0,
       end_reached: true,
       stats: %{total: 0, drafts: 0},
       ai: Ordo.AI.available?(),
       page_title: "Ordo — #{tenant.name}"
     )
     |> stream(:tickets, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    channel_id = parse_int(params["ch"])
    tenant_id = socket.assigns.tenant.id
    first_page = Support.list_tickets(tenant_id, channel_id, limit: @per_page, offset: 0)

    socket =
      socket
      |> assign(
        channel_id: channel_id,
        page: 0,
        end_reached: length(first_page) < @per_page,
        stats: Support.ticket_stats(tenant_id, channel_id)
      )
      |> stream(:tickets, first_page, reset: true)

    case parse_int(params["id"]) do
      nil ->
        case first_page do
          [first | _] -> {:noreply, push_patch(socket, to: ticket_href(channel_id, first.id))}
          [] -> {:noreply, assign(socket, selected_id: nil, ticket: nil)}
        end

      id ->
        {:noreply, assign(socket, selected_id: id, ticket: Support.get_ticket(id))}
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s),
    do:
      (case Integer.parse(s) do
         {n, _} -> n
         _ -> nil
       end)

  defp ticket_href(nil, id), do: ~p"/inbox/#{id}"
  defp ticket_href(channel_id, id), do: ~p"/inbox/#{id}?#{[ch: channel_id]}"

  @impl true
  def handle_event("load_more", _params, %{assigns: %{end_reached: true}} = socket), do: {:noreply, socket}

  def handle_event("load_more", _params, socket) do
    page = socket.assigns.page + 1

    more =
      Support.list_tickets(socket.assigns.tenant.id, socket.assigns.channel_id,
        limit: @per_page,
        offset: page * @per_page
      )

    {:noreply,
     socket
     |> assign(page: page, end_reached: length(more) < @per_page)
     |> stream(:tickets, more, at: -1)}
  end

  # approve/take_over update via the broadcast → handle_info, which refreshes the stream row + detail.
  def handle_event("approve", %{"body" => body}, socket) do
    if socket.assigns.ticket, do: Support.approve_and_send(socket.assigns.ticket, body)
    {:noreply, socket}
  end

  def handle_event("take_over", _params, socket) do
    if socket.assigns.ticket, do: Support.take_over(socket.assigns.ticket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ticket_created, ticket}, socket) do
    {:noreply, socket |> stream_insert(:tickets, ticket, at: 0) |> refresh_stats()}
  end

  def handle_info({:ticket_updated, ticket}, socket) do
    socket = socket |> stream_insert(:tickets, ticket) |> refresh_stats()

    socket =
      if socket.assigns.selected_id == ticket.id, do: assign(socket, ticket: Support.get_ticket(ticket.id)), else: socket

    {:noreply, socket}
  end

  def handle_info(:inbox_cleared, socket) do
    {:noreply,
     socket
     |> stream(:tickets, [], reset: true)
     |> assign(selected_id: nil, ticket: nil)
     |> refresh_stats()}
  end

  defp refresh_stats(socket),
    do: assign(socket, stats: Support.ticket_stats(socket.assigns.tenant.id, socket.assigns.channel_id))

  @impl true
  def render(assigns) do
    current = assigns.channel_id && Enum.find(assigns.channels, &(&1.id == assigns.channel_id))

    assigns =
      assigns
      |> assign(:current_label, channel_label(current))
      |> assign(:ticket_type, assigns.ticket && Ticket.channel_type(assigns.ticket))

    ~H"""
    <div class="bg-paper text-ink font-body antialiased h-screen overflow-hidden flex flex-col">
      <!-- TOP BAR -->
      <header class="h-14 bg-paper-card border-b-2 border-ink flex items-center px-5 gap-4 relative z-30 shrink-0">
        <span class="font-mono font-semibold tracking-[0.3em] text-base select-none">
          ORDO<span class="text-label-deep">.</span>
        </span>
        <span class="text-slate-300">|</span>

        <div class="relative">
          <button
            phx-click={JS.toggle(to: "#mbx-menu")}
            class="flex items-center gap-2 text-sm text-ink-soft hover:text-ink px-2 py-1.5 rounded hover:bg-paper"
          >
            <span class="font-mono">{@current_label}</span>
            <svg class="w-3 h-3 text-ink-mute" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2.5"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </button>
          <div
            id="mbx-menu"
            phx-click-away={JS.hide(to: "#mbx-menu")}
            class="hidden absolute top-full left-0 mt-1 w-72 bg-paper-card border border-slate-200 shadow-lg rounded-sm py-1"
          >
            <p class="px-4 pt-2 pb-1 font-mono text-[10px] tracking-[0.2em] text-ink-mute">
              {gettext("CHANNELS")}
            </p>
            <button
              phx-click={JS.patch(~p"/inbox") |> JS.hide(to: "#mbx-menu")}
              class="w-full text-left px-4 py-2 hover:bg-paper flex items-center justify-between"
            >
              <span class="font-mono text-sm">{gettext("All channels")}</span>
              <span class="font-mono text-[10px] text-label-deep">
                {@stats.drafts} {gettext("draft")}
              </span>
            </button>
            <button
              :for={c <- @channels}
              phx-click={JS.patch(~p"/inbox?#{[ch: c.id]}") |> JS.hide(to: "#mbx-menu")}
              class="w-full text-left px-4 py-2 hover:bg-paper flex items-center justify-between"
            >
              <span class="font-mono text-sm">{channel_label(c)}</span>
              <span class="font-mono text-[10px] text-ink-mute">
                {if c.active, do: gettext("active"), else: "—"}
              </span>
            </button>
          </div>
        </div>

        <div class="ml-auto flex items-center gap-1">
          <button
            phx-click={
              JS.remove_class("sheet-hidden", to: "#rules-sheet") |> JS.show(to: "#rules-backdrop")
            }
            class="px-3 py-1.5 text-sm text-ink-soft hover:bg-paper rounded"
          >
            {gettext("Shop rules")}
          </button>
          <.link
            navigate={~p"/settings"}
            title={gettext("Settings")}
            class="p-2 text-ink-mute hover:text-ink hover:bg-paper rounded block"
          >
            <svg
              class="w-[18px] h-[18px]"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
          </.link>
          <span class="w-px h-5 bg-slate-200 mx-1"></span>
          <Layouts.locale_switcher locale={@locale} />
          <Layouts.account_menu current_scope={@current_scope} id="inbox-account-menu" />
        </div>
      </header>

      <div class="flex flex-1 min-h-0">
        <!-- LEFT: ticket list -->
        <aside class="w-[300px] shrink-0 border-r border-slate-200 bg-paper-card flex flex-col">
          <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
            <span class="font-mono text-[11px] tracking-[0.2em] text-ink-mute">
              {gettext("TICKETS")}
            </span>
            <span class="font-mono text-[11px] text-ink-mute">
              {@stats.total} · <span class="text-label-deep">{@stats.drafts} {gettext("draft")}</span>
            </span>
          </div>

          <p :if={@stats.total == 0} class="px-4 py-6 text-sm text-ink-mute">
            {gettext("Empty. Import a mailbox in Settings (⚙).")}
          </p>

          <div class="overflow-y-auto flex-1">
            <div id="tickets" phx-update="stream" class="divide-y divide-slate-100">
              <.link
                :for={{dom_id, t} <- @streams.tickets}
                id={dom_id}
                patch={ticket_href(@channel_id, t.id)}
                class={[
                  "block w-full text-left px-4 py-3 border-l-[3px]",
                  ticket_row_class(t, @selected_id)
                ]}
              >
                <div class="flex items-baseline justify-between gap-2">
                  <span class="font-semibold text-sm truncate">
                    {t.customer_name || t.customer_email}
                  </span>
                  <span class={[
                    "font-mono text-[10px] shrink-0",
                    (t.status == "answered" && "text-okay") || "text-ink-mute"
                  ]}>
                    {if t.status == "answered", do: "✓ ", else: ""}{time_of(t)}
                  </span>
                </div>
                <p
                  :if={Ticket.channel_type(t) == "gbp"}
                  class="font-mono text-[11px] text-label-deep mt-0.5"
                >
                  {stars(t.meta["rating"])}
                </p>
                <p class="text-sm text-ink-soft truncate mt-0.5">{t.subject}</p>
                <% {label, cls} = badge(t) %>
                <span class="inline-flex items-center gap-1 mt-1.5">
                  <span
                    :if={Ticket.channel_type(t) == "gbp"}
                    class="font-mono text-[10px] text-ink-mute"
                    title="Google"
                  >
                    ★G
                  </span>
                  <span class={["inline-block font-mono text-[10px] px-1.5 py-0.5 border", cls]}>
                    {label}
                  </span>
                </span>
              </.link>
            </div>

            <div
              :if={!@end_reached}
              id="load-more"
              phx-viewport-bottom="load_more"
              class="px-4 py-3 text-center font-mono text-[11px] text-ink-mute"
            >
              <span class="inline-block animate-pulse">{gettext("● loading…")}</span>
            </div>
          </div>
        </aside>
        
    <!-- RIGHT: card layout -->
        <main class="flex-1 min-w-0 overflow-y-auto">
          <div
            :if={@ticket == nil}
            class="h-full flex items-center justify-center text-sm text-ink-mute"
          >
            {gettext("Select a ticket from the list.")}
          </div>

          <div :if={@ticket} class="max-w-4xl mx-auto px-6 py-6 space-y-5">
            <!-- GBP review card -->
            <div :if={@ticket_type == "gbp"} class="bg-paper-card shadow-card rounded-sm">
              <div class="px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                <span class="font-mono text-xs tracking-wide">{gettext("REVIEW")} · Google</span>
                <span class="font-mono text-xs text-label-deep">
                  {stars(@ticket.meta["rating"])} · {@ticket.meta["posted"]}
                </span>
              </div>
              <div class="px-4 py-4">
                <p class="font-mono text-[11px] text-ink-mute mb-2">
                  {@ticket.customer_name} · {@ticket.meta["author_kind"]}
                </p>
                <div
                  :for={m <- customer_messages(@ticket)}
                  class="bg-slate-100 rounded-sm px-4 py-3 text-[15px] leading-relaxed whitespace-pre-wrap"
                >
                  {m.body}
                </div>
              </div>
            </div>

            <div :if={@ticket_type != "gbp"} class="grid grid-cols-1 lg:grid-cols-2 gap-5">
              <!-- customer message card -->
              <div class="bg-paper-card shadow-card rounded-sm">
                <div class="px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                  <span class="font-mono text-xs tracking-wide">TICKET&nbsp;#{@ticket.id}</span>
                  <span class="font-mono text-xs text-ink-mute truncate">
                    {@ticket.customer_email}
                  </span>
                </div>
                <div class="px-4 py-4 space-y-4">
                  <div :for={m <- customer_messages(@ticket)}>
                    <p class="font-mono text-[11px] text-ink-mute mb-2">
                      {time_of(m)} · {@ticket.customer_name || gettext("Customer")}
                    </p>
                    <div class="bg-slate-100 rounded-sm px-4 py-3 text-[15px] leading-relaxed whitespace-pre-wrap">
                      {m.body}
                    </div>
                  </div>
                </div>
              </div>
              
    <!-- baselinker card -->
              <div class="bg-paper-card shadow-card rounded-sm">
                <div class="px-4 py-2.5 border-b border-slate-200">
                  <span class="font-mono text-xs tracking-wide">BASELINKER</span>
                </div>
                <div class="px-4 py-3 font-mono text-[13px]">
                  <div :if={@ticket.order}>
                    <div class="flex justify-between py-1">
                      <span class="text-ink-mute">{gettext("no.")}</span><span>{@ticket.order["number"]}</span>
                    </div>
                    <div class="flex justify-between py-1">
                      <span class="text-ink-mute">{gettext("date")}</span><span>{@ticket.order["date"]}</span>
                    </div>
                    <div class="flex justify-between py-1">
                      <span class="text-ink-mute">{gettext("status")}</span><span>{@ticket.order["status"]}</span>
                    </div>
                    <div :if={@ticket.order["tracking"]} class="flex justify-between py-1">
                      <span class="text-ink-mute">{@ticket.order["courier"]}</span><span>{@ticket.order["tracking"]}</span>
                    </div>
                    <div
                      :if={@ticket.order["courier_history"] not in [nil, []]}
                      class="border-t border-slate-200 mt-2 pt-2 text-[12px]"
                    >
                      <div
                        :for={h <- @ticket.order["courier_history"]}
                        class="flex justify-between py-0.5"
                      >
                        <span class="text-ink-mute">{h["status"]}</span><span class="text-ink-mute">{h["date"]}</span>
                      </div>
                    </div>
                  </div>
                  <p :if={is_nil(@ticket.order)} class="text-[12px] text-ink-mute font-body">
                    {if @ticket.status in ~w(new classified),
                      do: gettext("Looking up the order…"),
                      else: gettext("No order found for this address.")}
                  </p>
                </div>
              </div>
            </div>
            
    <!-- answer card -->
            <div class="bg-paper-card shadow-card rounded-sm">
              <div class="px-4 py-2.5 border-b border-slate-200 flex items-center justify-between">
                <span class="font-mono text-xs tracking-wide">{gettext("REPLY")}</span>
                <span :if={@ticket.category} class="font-mono text-xs text-label-deep">
                  {category_label(@ticket.category)}
                </span>
              </div>
              <div class="px-4 py-4">
                <div :if={@ticket.status in ~w(new classified)} class="text-sm text-ink-mute">
                  <span class="inline-block animate-pulse">{gettext("● Ordo is working…")}</span>
                </div>

                <form :if={@ticket.status == "draft_ready"} phx-submit="approve">
                  <textarea
                    name="body"
                    class="w-full bg-slate-50 border border-slate-200 rounded-sm px-4 py-3 text-[15px] leading-relaxed outline-none focus:ring-2 focus:ring-label min-h-[180px] resize-y"
                  >{@ticket.draft}</textarea>
                  <div class="flex items-center gap-3 mt-4">
                    <button
                      type="submit"
                      class="bg-ink text-white font-mono text-sm px-5 py-2.5 hover:bg-ink-soft transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
                    >
                      {if @ticket_type == "gbp",
                        do: gettext("Approve and publish"),
                        else: gettext("Approve and send")}
                    </button>
                    <button
                      type="button"
                      phx-click="take_over"
                      class="font-mono text-[12px] text-ink-mute hover:text-ink"
                    >
                      {gettext("take over")}
                    </button>
                    <span class="ml-auto font-mono text-[12px] text-ink-mute">
                      {gettext("edit the text above if needed")}
                    </span>
                  </div>
                </form>

                <div :if={@ticket.status == "answered"}>
                  <div class="bg-slate-50 border border-slate-200 rounded-sm px-4 py-3 text-[15px] leading-relaxed whitespace-pre-wrap">
                    {@ticket.draft}
                  </div>
                  <p class="font-mono text-[12px] text-okay mt-3">
                    {gettext("✓ sent · %{count} s", count: @ticket.resolution_seconds)}
                  </p>
                </div>

                <p
                  :if={@ticket_type == "gbp"}
                  class="font-mono text-[11px] text-ink-mute mt-4 pt-3 border-t border-slate-100"
                >
                  {gettext(
                    "Negative reviews are never published automatically — a human always approves them."
                  )}
                </p>
              </div>
            </div>
          </div>
        </main>
      </div>
      
    <!-- RULES SHEET -->
      <div
        id="rules-backdrop"
        phx-click={JS.add_class("sheet-hidden", to: "#rules-sheet") |> JS.hide(to: "#rules-backdrop")}
        class="hidden fixed inset-0 bg-ink/30 z-40"
      >
      </div>
      <aside
        id="rules-sheet"
        class="sheet sheet-hidden fixed top-0 right-0 h-full w-[400px] max-w-full bg-paper-card border-l border-slate-200 shadow-2xl z-50 flex flex-col"
      >
        <div class="px-5 py-4 border-b-2 border-ink flex items-center justify-between">
          <div>
            <p class="font-mono text-[11px] tracking-[0.2em] text-ink-mute">
              {gettext("SHOP RULES")}
            </p>
            <p class="font-semibold text-sm mt-0.5">{@tenant.name}</p>
          </div>
          <button
            phx-click={
              JS.add_class("sheet-hidden", to: "#rules-sheet") |> JS.hide(to: "#rules-backdrop")
            }
            class="p-2 text-ink-mute hover:text-ink hover:bg-paper rounded"
            aria-label={gettext("Close")}
          >
            ✕
          </button>
        </div>
        <p class="px-5 py-3 text-[13px] text-ink-soft border-b border-slate-100">
          {gettext("Ordo bases its replies on these facts.")}
          <strong>{gettext("It doesn't make anything up beyond them.")}</strong>
        </p>
        <div class="flex-1 overflow-y-auto divide-y divide-slate-100">
          <div
            :for={f <- @tenant.policy_facts}
            class="px-5 py-3 flex items-start justify-between gap-3"
          >
            <div>
              <p class="text-sm font-medium">{f.label}</p>
              <p class="text-sm text-ink-soft">{f.value}{if f.unit, do: " " <> f.unit, else: ""}</p>
            </div>
            <span
              :if={f.category}
              class="font-mono text-[10px] px-1.5 py-0.5 border border-slate-300 text-ink-mute shrink-0 mt-0.5"
            >
              {String.upcase(category_label(f.category))}
            </span>
          </div>
        </div>
      </aside>
    </div>
    """
  end

  defp channel_label(nil), do: gettext("All channels")
  defp channel_label(%{type: "gbp"}), do: gettext("Google reviews")
  defp channel_label(%{email: email}), do: email

  defp category_label("PACKAGE_STATUS"), do: gettext("Package status")
  defp category_label("RETURN"), do: gettext("Return")
  defp category_label("RETURN_STATUS"), do: gettext("Return status")
  defp category_label("INVOICE"), do: gettext("Invoice")
  defp category_label("ORDER_CHANGE"), do: gettext("Order change")
  defp category_label("CANCELLATION"), do: gettext("Cancellation")
  defp category_label("COMPLAINT"), do: gettext("Complaint")
  defp category_label("OTHER"), do: gettext("Other")
  defp category_label("REVIEW_POSITIVE"), do: gettext("Thank-you")
  defp category_label("REVIEW_NEGATIVE"), do: gettext("Negative")
  defp category_label("REVIEW_MIXED"), do: gettext("Mixed")
  defp category_label(code), do: code

  defp stars(rating) when is_integer(rating) and rating in 0..5,
    do: String.duplicate("★", rating) <> String.duplicate("☆", 5 - rating)

  defp stars(_), do: "★★★★★"

  defp time_of(%{inserted_at: at}), do: Calendar.strftime(at, "%H:%M")

  defp customer_messages(ticket), do: Enum.filter(ticket.messages, &(&1.role == "customer"))

  defp ticket_row_class(t, selected_id) do
    cond do
      t.id == selected_id -> "bg-paper border-label"
      t.status == "answered" -> "border-transparent hover:bg-paper opacity-60"
      true -> "border-transparent hover:bg-paper"
    end
  end

  defp badge(%{status: "answered"} = t),
    do: {gettext("SENT · %{count} s", count: t.resolution_seconds), "border-okay text-okay"}

  defp badge(%{category: "COMPLAINT"}), do: {gettext("COMPLAINT · HUMAN"), "border-label-deep text-label-deep"}
  defp badge(%{category: "REVIEW_NEGATIVE"}), do: {gettext("NEGATIVE · HUMAN"), "border-label-deep text-label-deep"}
  defp badge(%{category: nil}), do: {"…", "border-slate-300 text-ink-mute"}
  defp badge(%{category: c}), do: {String.upcase(category_label(c)), "border-slate-300 text-ink-mute"}
end
