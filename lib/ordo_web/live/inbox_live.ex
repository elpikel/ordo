defmodule OrdoWeb.InboxLive do
  @moduledoc "Demo support panel: artificial inbox → ticket → BL context → draft → approve."
  use OrdoWeb, :live_view

  alias Ordo.Support

  @presets %{
    "anna" => %{
      customer_name: "Anna Kowalska",
      customer_email: "anna.kowalska@gmail.com",
      subject: "Gdzie moja paczka?",
      body: "Dzień dobry, zamówiłam tydzień temu i wciąż nic nie dotarło. Gdzie jest moja przesyłka? Pozdrawiam, Anna Kowalska"
    },
    "tomasz" => %{
      customer_name: "Tomasz Kaczmarek",
      customer_email: "t.kaczmarek@gmail.com",
      subject: "Chcę zwrócić masło orzechowe",
      body: "Witam, zamówiłem masło orzechowe (ZAM-50106) ale jednak chciałbym je zwrócić. Jak to zrobić?"
    }
  }

  @impl true
  def mount(%{"tenant" => param}, _session, socket) do
    if connected?(socket), do: Support.subscribe()

    tenant = Support.fetch_tenant!(param)
    tickets = Support.list_tickets(tenant.id)

    {:ok,
     assign(socket,
       tenant: tenant,
       tickets: tickets,
       selected_id: nil,
       composing: false,
       ai: Ordo.AI.available?(),
       page_title: "Ordo — #{tenant.name}"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_id =
      case params["id"] && Integer.parse(params["id"]) do
        {id, _} -> id
        _ -> nil
      end

    {:noreply, assign(socket, selected_id: selected_id)}
  end

  @impl true
  def handle_event("simulate", %{"who" => who}, socket) do
    {:ok, ticket} = Support.receive_email(socket.assigns.tenant.id, @presets[who])
    {:noreply, socket |> assign(tickets: tickets(socket)) |> push_patch(to: ~p"/#{socket.assigns.tenant.slug}/inbox/#{ticket.id}")}
  end

  def handle_event("import_mailbox", _params, socket) do
    Support.import_demo_mailbox!(socket.assigns.tenant)
    {:noreply, socket |> assign(tickets: []) |> push_patch(to: ~p"/#{socket.assigns.tenant.slug}/inbox")}
  end

  def handle_event("clear_inbox", _params, socket) do
    Support.clear_inbox!(socket.assigns.tenant.id)
    {:noreply, socket |> assign(tickets: []) |> push_patch(to: ~p"/#{socket.assigns.tenant.slug}/inbox")}
  end

  def handle_event("toggle_compose", _params, socket) do
    {:noreply, assign(socket, composing: !socket.assigns.composing)}
  end

  def handle_event("open_compose", _params, socket) do
    {:noreply, assign(socket, composing: true)}
  end

  def handle_event("compose", %{"email" => params}, socket) do
    attrs = %{
      customer_name: blank_to_nil(params["customer_name"]),
      customer_email: default(params["customer_email"], "klient@example.com"),
      subject: default(params["subject"], "(bez tematu)"),
      body: params["body"] || ""
    }

    {:ok, ticket} = Support.receive_email(socket.assigns.tenant.id, attrs)

    {:noreply,
     socket |> assign(tickets: tickets(socket), composing: false) |> push_patch(to: ~p"/#{socket.assigns.tenant.slug}/inbox/#{ticket.id}")}
  end

  def handle_event("approve", %{"draft" => %{"body" => body}}, socket) do
    if ticket = selected(socket) do
      {:ok, _} = Support.approve_and_send(ticket, body)
    end

    {:noreply, assign(socket, tickets: tickets(socket))}
  end

  @impl true
  def handle_info({event, _ticket}, socket) when event in [:ticket_created, :ticket_updated] do
    {:noreply, assign(socket, tickets: tickets(socket))}
  end

  def handle_info(:inbox_cleared, socket) do
    {:noreply, assign(socket, tickets: tickets(socket))}
  end

  defp tickets(socket), do: Support.list_tickets(socket.assigns.tenant.id)

  defp selected(socket) do
    Enum.find(socket.assigns.tickets, &(&1.id == socket.assigns.selected_id))
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :ticket, Enum.find(assigns.tickets, &(&1.id == assigns.selected_id)))

    ~H"""
    <div class="min-h-screen bg-paper text-ink font-body">
      <header class="max-w-6xl mx-auto px-5 sm:px-8 py-5 flex flex-wrap items-center justify-between gap-3">
        <div class="font-mono font-medium tracking-[0.35em] text-lg select-none">
          ORDO<span class="text-label-deep">.</span>
          <span class="ml-3 font-body font-normal text-xs text-ink-mute tracking-normal">skrzynka · {@tenant.name}</span>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <span class={["font-mono text-[11px] px-2 py-1 border", @ai && "text-okay border-okay" || "text-ink-mute border-slate-400"]}>
            {if @ai, do: "AI: OpenAI", else: "AI: fallback"}
          </span>
          <button phx-click="import_mailbox"
                  class="font-mono text-sm bg-ink text-paper px-3 py-2 hover:bg-ink-soft transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-label">
            ↓ Importuj skrzynkę
          </button>
          <button phx-click="clear_inbox"
                  class="font-mono text-sm border border-ink px-3 py-2 hover:bg-ink hover:text-paper transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-label">
            Wyczyść
          </button>
          <button phx-click={JS.toggle(to: "#rules-drawer")}
                  class="font-mono text-sm border border-ink px-3 py-2 hover:bg-ink hover:text-paper transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-label">
            Zasady sklepu
          </button>
          <div class="relative">
            <button phx-click={JS.toggle(to: "#new-menu")}
                    class="font-mono text-sm border border-ink px-3 py-2 hover:bg-ink hover:text-paper transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-label">
              ✎ Nowy e-mail ▾
            </button>
            <div id="new-menu" phx-click-away={JS.hide(to: "#new-menu")}
                 class="hidden absolute right-0 mt-1 w-60 bg-paper-card border border-ink shadow-[6px_6px_0_0_#16233B14] z-20">
              <button phx-click={JS.hide(to: "#new-menu") |> JS.push("simulate", value: %{who: "anna"})}
                      class="block w-full text-left px-4 py-2.5 text-sm hover:bg-slate-100 border-b border-slate-200">
                Anna — „gdzie moja paczka?"
              </button>
              <button phx-click={JS.hide(to: "#new-menu") |> JS.push("simulate", value: %{who: "tomasz"})}
                      class="block w-full text-left px-4 py-2.5 text-sm hover:bg-slate-100 border-b border-slate-200">
                Tomasz — zwrot masła
              </button>
              <button phx-click={JS.hide(to: "#new-menu") |> JS.push("open_compose")}
                      class="block w-full text-left px-4 py-2.5 text-sm hover:bg-slate-100 font-medium">
                ✎ Napisz własny…
              </button>
            </div>
          </div>
        </div>
      </header>
      <div class="perf max-w-6xl mx-auto"></div>

      <!-- Zasady sklepu — slide-over drawer (client-side toggle) -->
      <div id="rules-drawer" class="hidden fixed inset-0 z-30">
        <div class="absolute inset-0 bg-ink/20" phx-click={JS.hide(to: "#rules-drawer")}></div>
        <div class="absolute inset-y-0 right-0 w-full max-w-sm bg-paper-card border-l border-slate-300 shadow-2xl p-6 overflow-y-auto">
          <div class="flex items-center justify-between mb-5">
            <p class="font-mono text-xs tracking-[0.2em] text-ink-mute uppercase">Zasady sklepu · {@tenant.name}</p>
            <button phx-click={JS.hide(to: "#rules-drawer")} class="text-ink-mute hover:text-ink text-lg leading-none">✕</button>
          </div>
          <p class="text-xs text-ink-mute mb-4">Na tych faktach Ordo opiera odpowiedzi. Nie zmyśla poza nimi.</p>
          <ul class="space-y-3 text-sm">
            <li :for={f <- @tenant.policy_facts} class="border-b border-slate-100 pb-3">
              <div class="flex justify-between gap-4">
                <span class="text-ink-mute">{f.label}</span>
                <span class="text-ink text-right font-medium">{f.value}{if f.unit, do: " " <> f.unit, else: ""}</span>
              </div>
              <span :if={f.category} class="text-[11px] text-label-deep">{category_label(f.category)}</span>
            </li>
          </ul>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-5 sm:px-8 pt-8 pb-16 grid lg:grid-cols-3 gap-6">
        <!-- Ticket list -->
        <div class="space-y-2">
          <form :if={@composing} phx-submit="compose"
                class="bg-paper-card border border-ink shadow-[6px_6px_0_0_#16233B14] p-4 mb-4 space-y-2">
            <p class="font-display font-bold text-sm mb-1">Nowy e-mail do skrzynki</p>
            <input name="email[customer_name]" placeholder="Imię i nazwisko"
                   class="w-full border border-slate-300 bg-paper px-3 py-2 text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-label" />
            <input name="email[customer_email]" placeholder="e-mail klienta"
                   class="w-full border border-slate-300 bg-paper px-3 py-2 text-sm font-mono focus:outline-none focus-visible:ring-2 focus-visible:ring-label" />
            <input name="email[subject]" placeholder="Temat"
                   class="w-full border border-slate-300 bg-paper px-3 py-2 text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-label" />
            <textarea name="email[body]" rows="4" placeholder="Treść wiadomości…"
                      class="w-full border border-slate-300 bg-paper px-3 py-2 text-sm leading-snug focus:outline-none focus-visible:ring-2 focus-visible:ring-label"></textarea>
            <div class="flex items-center gap-2">
              <button type="submit" class="bg-ink text-paper font-mono text-sm px-4 py-2 hover:bg-ink-soft transition-colors">
                Wrzuć do skrzynki
              </button>
              <button type="button" phx-click="toggle_compose" class="font-mono text-xs text-ink-mute hover:text-ink">
                anuluj
              </button>
            </div>
          </form>

          <p class="font-mono text-xs tracking-[0.2em] text-ink-mute uppercase mb-2">Tickety</p>
          <div class="space-y-2 overflow-y-auto pr-1 max-h-[70vh]">
          <p :if={@tickets == []} class="text-sm text-ink-mute">
            Pusto. Kliknij „✎ Nowy e-mail" u góry, aby wrzucić e-mail do skrzynki.
          </p>
          <button :for={t <- @tickets} phx-click={JS.patch(~p"/#{@tenant.slug}/inbox/#{t.id}")}
                  class={["w-full text-left border bg-paper-card px-4 py-3 transition-colors",
                          @selected_id == t.id && "border-ink" || "border-slate-300 hover:border-slate-400"]}>
            <div class="flex items-center justify-between">
              <span class="font-medium text-sm">{t.customer_name || t.customer_email}</span>
              <.status_pill status={t.status} />
            </div>
            <div class="text-xs text-ink-mute truncate mt-0.5">{t.subject}</div>
            <span :if={t.category} class="inline-block mt-1.5 text-[11px] text-label-deep border border-label px-1.5 py-0.5">
              {category_label(t.category)}
            </span>
          </button>
          </div>
        </div>

        <!-- Detail -->
        <div class="lg:col-span-2">
          <div :if={@ticket == nil} class="text-sm text-ink-mute border border-dashed border-slate-300 p-8 text-center">
            Wybierz ticket z listy.
          </div>

          <div :if={@ticket} class="space-y-4">
            <!-- Thread + BL data -->
            <div class="grid md:grid-cols-2 gap-4">
              <div class="bg-paper-card border border-slate-300 shadow-[6px_6px_0_0_#16233B14]">
                <div class="flex items-center justify-between px-4 py-2 border-b border-slate-200">
                  <span class="font-mono text-xs text-ink-mute">TICKET&nbsp;#{@ticket.id}</span>
                  <span class="font-mono text-xs text-ink-mute">{@ticket.customer_email}</span>
                </div>
                <div class="px-4 py-3 space-y-3 text-sm">
                  <div :for={m <- @ticket.messages}>
                    <p class="font-mono text-[10px] text-ink-mute mb-1">
                      {if m.role == "customer", do: @ticket.customer_name || "Klient", else: "Ordo"}
                    </p>
                    <p class={["px-3 py-2 leading-snug whitespace-pre-wrap",
                               m.role == "customer" && "bg-slate-100" || "bg-ink text-paper"]}>{m.body}</p>
                  </div>
                </div>
              </div>

              <div class="bg-paper-card border border-slate-300 shadow-[6px_6px_0_0_#16233B14]">
                <div class="px-4 py-2 border-b border-slate-200 font-mono text-xs text-ink-mute">
                  BASELINKER
                </div>
                <div class="px-4 py-3 text-sm">
                  <div :if={@ticket.order == nil} class="text-ink-mute">
                    <span :if={@ticket.status in ~w(new classified)}>Szukam zamówienia…</span>
                    <span :if={@ticket.status not in ~w(new classified)}>Nie znaleziono zamówienia dla tego adresu.</span>
                  </div>
                  <div :if={@ticket.order} class="space-y-2 font-mono text-[13px]">
                    <div class="flex justify-between"><span class="text-ink-mute">nr</span><span>{@ticket.order["number"]}</span></div>
                    <div class="flex justify-between"><span class="text-ink-mute">data</span><span>{@ticket.order["date"]}</span></div>
                    <div class="flex justify-between"><span class="text-ink-mute">status</span><span>{@ticket.order["status"]}</span></div>
                    <div :if={@ticket.order["tracking"]} class="flex justify-between">
                      <span class="text-ink-mute">{@ticket.order["courier"]}</span><span class="text-ink">{@ticket.order["tracking"]}</span>
                    </div>
                    <div :if={@ticket.order["courier_history"] != []} class="pt-1 border-t border-slate-200 space-y-1">
                      <div :for={h <- @ticket.order["courier_history"]} class="flex justify-between text-[11px] text-ink-mute">
                        <span>{h["status"]}</span><span>{h["date"]}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Draft / answer -->
            <div class="bg-paper-card border border-slate-300 shadow-[6px_6px_0_0_#16233B14] relative">
              <div class="px-4 py-2 border-b border-slate-200 font-mono text-xs text-ink-mute flex items-center justify-between">
                <span>ODPOWIEDŹ</span>
                <span :if={@ticket.category} class="text-label-deep">{category_label(@ticket.category)}</span>
              </div>

              <div :if={@ticket.status in ~w(new classified)} class="px-4 py-6 text-sm text-ink-mute">
                <span class="inline-block animate-pulse">● Ordo pracuje… {stage_label(@ticket.status)}</span>
              </div>

              <div :if={@ticket.status == "needs_human"} class="px-4 py-4">
                <p class="text-xs text-ink-mute mb-2">Kategoria bez auto-draftu — napisz odpowiedź ręcznie.</p>
                <.answer_form ticket={@ticket} />
              </div>

              <div :if={@ticket.status == "draft_ready"} class="px-4 py-4">
                <.answer_form ticket={@ticket} />
              </div>

              <div :if={@ticket.status == "answered"} class="px-4 py-4">
                <p class="bg-ink text-paper px-3 py-2 text-sm leading-snug whitespace-pre-wrap">{@ticket.draft}</p>
                <div class="mt-3 flex items-center justify-between">
                  <span class="font-mono text-[11px] text-ink-mute">zatwierdzone i wysłane<span class="cursor-blink">_</span></span>
                  <span class="font-mono text-[11px] text-okay">{@ticket.resolution_seconds}&nbsp;s</span>
                </div>
                <div class="stamp absolute -top-3 right-4 border-[3px] border-okay text-okay font-mono font-medium tracking-[0.2em] text-xs px-2 py-0.5 bg-paper-card">
                  ROZWIĄZANO
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- function components ---

  attr :ticket, :map, required: true

  defp answer_form(assigns) do
    ~H"""
    <form phx-submit="approve" class="space-y-3">
      <textarea name="draft[body]" rows="6"
                class="w-full border border-slate-300 bg-paper px-3 py-2 text-sm leading-snug focus:outline-none focus-visible:ring-2 focus-visible:ring-label">{@ticket.draft}</textarea>
      <div class="flex items-center gap-3">
        <button type="submit"
                class="bg-ink text-paper font-mono text-sm px-5 py-2 hover:bg-ink-soft transition-colors">
          Zatwierdź i wyślij
        </button>
        <span class="font-mono text-[11px] text-ink-mute">edytuj tekst powyżej, jeśli trzeba</span>
      </div>
    </form>
    """
  end

  attr :status, :string, required: true

  defp status_pill(assigns) do
    {label, cls} =
      case assigns.status do
        "answered" -> {"rozwiązano", "text-okay border-okay"}
        "draft_ready" -> {"draft", "text-ink border-ink"}
        "needs_human" -> {"człowiek", "text-label-deep border-label-deep"}
        _ -> {"…", "text-ink-mute border-slate-400"}
      end

    assigns = assign(assigns, label: label, cls: cls)

    ~H"""
    <span class={["font-mono text-[10px] px-1.5 py-0.5 border", @cls]}>{@label}</span>
    """
  end

  defp stage_label("new"), do: "odczyt e-maila"
  defp stage_label("classified"), do: "pobieram dane z BaseLinkera"
  defp stage_label(_), do: "…"

  @category_labels %{
    "PACKAGE_STATUS" => "Status paczki",
    "RETURN" => "Zwrot",
    "RETURN_STATUS" => "Status zwrotu",
    "INVOICE" => "Faktura",
    "ORDER_CHANGE" => "Zmiana zamówienia",
    "CANCELLATION" => "Anulacja",
    "COMPLAINT" => "Reklamacja",
    "OTHER" => "Inne"
  }

  defp category_label(code), do: Map.get(@category_labels, code, code)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v), do: if(String.trim(v) == "", do: nil, else: v)
  defp default(v, fallback), do: blank_to_nil(v) || fallback
end
