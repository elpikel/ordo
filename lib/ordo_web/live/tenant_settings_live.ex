defmodule OrdoWeb.TenantSettingsLive do
  @moduledoc "Per-tenant setup: BaseLinker token + mailboxes (+ demo controls). Tenant comes from current_scope."
  use OrdoWeb, :live_view

  alias Ordo.Mailboxes
  alias Ordo.Support

  @blank_mb %{id: nil, email: "", imap_host: "", imap_port: "993", username: "", smtp_host: "", smtp_port: "587"}

  @presets %{
    "anna" => %{
      customer_name: "Anna Kowalska",
      customer_email: "anna.kowalska@gmail.com",
      subject: "Gdzie moja paczka?",
      body: "Dzień dobry, zamówiłam tydzień temu i wciąż nic nie dotarło. Gdzie jest moja przesyłka? Pozdrawiam, Anna"
    },
    "tomasz" => %{
      customer_name: "Tomasz Kaczmarek",
      customer_email: "t.kaczmarek@gmail.com",
      subject: "Chcę zwrócić masło orzechowe",
      body: "Witam, zamówiłem masło orzechowe (ZAM-50106) ale jednak chciałbym je zwrócić. Jak to zrobić?"
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_scope.tenant

    {:ok,
     assign(socket,
       tenant: tenant,
       mailboxes: Mailboxes.list_for_tenant(tenant.id),
       editing_token: false,
       mb: @blank_mb,
       notice: nil,
       page_title: "Ordo — #{tenant.name} · ustawienia"
     )}
  end

  @impl true
  def handle_event("save_baselinker", %{"token" => token}, socket) do
    case String.trim(token) do
      "" ->
        {:noreply, notice(socket, "Podaj token.")}

      token ->
        {:ok, tenant} = Support.update_tenant(socket.assigns.tenant, %{bl_token: token})
        {:noreply, socket |> assign(tenant: tenant, editing_token: false) |> notice("Token BaseLinker zapisany.")}
    end
  end

  def handle_event("change_token", _params, socket), do: {:noreply, assign(socket, editing_token: true)}
  def handle_event("cancel_token", _params, socket), do: {:noreply, assign(socket, editing_token: false)}

  def handle_event("submit_mailbox", %{"mailbox" => params}, socket) do
    mb = socket.assigns.mb

    result =
      if mb.id do
        Mailboxes.update(Mailboxes.get!(mb.id), drop_blank_password(params))
      else
        Mailboxes.create(Map.put(params, "tenant_id", socket.assigns.tenant.id))
      end

    case result do
      {:ok, _} -> {:noreply, socket |> reload() |> assign(mb: @blank_mb) |> notice("Zapisano skrzynkę.")}
      {:error, cs} -> {:noreply, notice(socket, "Błąd: #{errors(cs)}")}
    end
  end

  def handle_event("edit_mailbox", %{"id" => id}, socket) do
    m = Mailboxes.get!(id)

    mb = %{
      id: m.id,
      email: m.email,
      imap_host: m.imap_host || "",
      imap_port: to_string(m.imap_port || 993),
      username: m.username || "",
      smtp_host: m.smtp_host || "",
      smtp_port: to_string(m.smtp_port || 587)
    }

    {:noreply, assign(socket, mb: mb)}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, mb: @blank_mb)}

  def handle_event("delete_mailbox", %{"id" => id}, socket) do
    Mailboxes.delete!(id)
    {:noreply, socket |> reload() |> assign(mb: @blank_mb) |> notice("Skrzynka usunięta.")}
  end

  def handle_event("import_mailbox", _params, socket) do
    Support.import_demo_mailbox!(socket.assigns.tenant)
    {:noreply, notice(socket, "Importuję skrzynkę — otwórz skrzynkę, aby zobaczyć.")}
  end

  def handle_event("clear_inbox", _params, socket) do
    Support.clear_inbox!(socket.assigns.tenant.id)
    {:noreply, notice(socket, "Wyczyszczono tickety.")}
  end

  def handle_event("simulate", %{"who" => who}, socket) do
    Support.receive_email(socket.assigns.tenant.id, @presets[who])
    {:noreply, notice(socket, "Wygenerowano e-mail — otwórz skrzynkę.")}
  end

  defp reload(socket), do: assign(socket, mailboxes: Mailboxes.list_for_tenant(socket.assigns.tenant.id))
  defp notice(socket, msg), do: assign(socket, notice: msg)

  defp drop_blank_password(params) do
    if String.trim(params["password"] || "") == "", do: Map.delete(params, "password"), else: params
  end

  defp errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp mask(token) when is_binary(token) and byte_size(token) >= 4, do: "••••••••••••" <> String.slice(token, -4, 4)

  defp mask(_), do: "••••••••••••"

  defp mailbox_status(m) do
    cond do
      m.last_error -> {"BŁĄD LOGOWANIA", "border-red-300 text-red-700"}
      m.active -> {"AKTYWNA", "border-okay text-okay"}
      true -> {"WYŁĄCZONA", "border-slate-300 text-ink-mute"}
    end
  end

  defp input_class,
    do:
      "w-full border border-slate-300 bg-paper-card px-3 py-2 font-mono text-sm placeholder:text-ink-mute focus:outline-none focus:ring-2 focus:ring-label"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-paper text-ink font-body antialiased min-h-screen">
      <header class="h-14 bg-paper-card border-b-2 border-ink flex items-center px-5 gap-4">
        <span class="font-mono font-semibold tracking-[0.3em] text-base select-none">
          ORDO<span class="text-label-deep">.</span>
        </span>
        <span class="text-slate-300">|</span>
        <span class="text-sm text-ink-soft">{@tenant.name} · ustawienia</span>
        <.link
          navigate={~p"/inbox"}
          class="ml-auto flex items-center gap-1.5 text-sm text-ink-soft hover:text-ink px-3 py-1.5 rounded hover:bg-paper"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          Wróć do skrzynki
        </.link>
        <span class="w-px h-5 bg-slate-200 mx-1"></span>
        <Layouts.account_menu current_scope={@current_scope} id="settings-account-menu" />
      </header>

      <main class="max-w-2xl mx-auto px-5 py-10 space-y-12">
        <p
          :if={@notice}
          class="font-mono text-sm text-okay border border-okay bg-paper-card px-4 py-2"
        >
          {@notice}
        </p>
        
    <!-- BaseLinker -->
        <section>
          <h2 class="font-mono text-[11px] tracking-[0.2em] text-ink-mute mb-1">BASELINKER</h2>
          <p class="text-sm text-ink-soft mb-4">
            Token API łączy Ordo z zamówieniami, przesyłkami i dokumentami sklepu. Wygenerujesz go w panelu BaseLinkera: Moje konto → API.
          </p>

          <div
            :if={!@tenant.bl_token || @editing_token}
            class="bg-paper-card border border-slate-200 rounded-sm px-4 py-4"
          >
            <div class="flex items-center gap-2 mb-3">
              <span class="font-mono text-[10px] px-2 py-0.5 border border-slate-300 text-ink-mute">
                BRAK TOKENU
              </span>
              <span class="text-[12px] text-ink-mute">połączenie z BaseLinkerem nieaktywne</span>
            </div>
            <form phx-submit="save_baselinker" class="flex gap-2">
              <input
                type="password"
                name="token"
                autocomplete="off"
                placeholder="wklej token API…"
                class={input_class()}
              />
              <button
                type="submit"
                class="bg-ink text-white font-mono text-sm px-4 py-2 hover:bg-ink-soft focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
              >
                Zapisz token
              </button>
              <button
                :if={@editing_token}
                type="button"
                phx-click="cancel_token"
                class="text-sm text-ink-mute hover:text-ink px-2"
              >
                Anuluj
              </button>
            </form>
            <p class="text-[12px] text-ink-mute mt-2">
              Token jest szyfrowany w bazie i nigdy nie jest wyświetlany ponownie.
            </p>
          </div>

          <div
            :if={@tenant.bl_token && !@editing_token}
            class="bg-paper-card border border-slate-200 rounded-sm px-4 py-4"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class="font-mono text-[10px] px-2 py-0.5 border border-okay text-okay">
                  POŁĄCZONO
                </span>
                <span class="font-mono text-sm text-ink-mute">token {mask(@tenant.bl_token)}</span>
              </div>
              <button
                phx-click="change_token"
                class="text-sm text-ink-soft hover:text-ink border border-slate-300 px-3 py-1 hover:bg-paper"
              >
                Zmień token
              </button>
            </div>
            <p class="text-[12px] text-ink-mute mt-2">
              Nowy token zapisywany jest tylko przy podaniu nowej wartości.
            </p>
          </div>
        </section>
        
    <!-- Mailboxes -->
        <section>
          <h2 class="font-mono text-[11px] tracking-[0.2em] text-ink-mute mb-1">SKRZYNKI E-MAIL</h2>
          <p class="text-sm text-ink-soft mb-4">
            Adresy, które Ordo monitoruje. Poczta pobierana jest z folderu INBOX co minutę.
          </p>

          <div
            :if={@mailboxes != []}
            class="bg-paper-card border border-slate-200 rounded-sm divide-y divide-slate-100"
          >
            <div :for={m <- @mailboxes} class="px-4 py-3 flex items-center justify-between gap-4">
              <div class="min-w-0">
                <p class="font-mono text-sm truncate">{m.email}</p>
                <p class="text-[12px] text-ink-mute mt-0.5">{m.imap_host}:{m.imap_port}</p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <% {label, cls} = mailbox_status(m) %>
                <span class={["font-mono text-[10px] px-2 py-0.5 border", cls]}>{label}</span>
                <button
                  phx-click="edit_mailbox"
                  phx-value-id={m.id}
                  class="text-sm text-ink-soft hover:text-ink border border-slate-300 px-3 py-1 hover:bg-paper"
                >
                  Edytuj
                </button>
                <button
                  phx-click="delete_mailbox"
                  phx-value-id={m.id}
                  data-confirm={"Usunąć skrzynkę #{m.email}?"}
                  class="text-sm text-red-700 border border-red-300 px-3 py-1 hover:bg-red-50"
                >
                  Usuń
                </button>
              </div>
            </div>
          </div>
          <div
            :if={@mailboxes == []}
            class="bg-paper-card border border-dashed border-slate-300 rounded-sm px-4 py-8 text-center"
          >
            <p class="text-sm text-ink-mute">Brak skrzynek. Dodaj pierwszą poniżej.</p>
          </div>

          <div class="mt-4 bg-paper-card border border-slate-200 rounded-sm px-4 py-4">
            <p class="text-sm font-semibold mb-3">
              {if @mb.id, do: "Edytuj skrzynkę: #{@mb.email}", else: "Dodaj skrzynkę"}
            </p>
            <form phx-submit="submit_mailbox" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="sm:col-span-2">
                <label class="block text-[12px] text-ink-mute mb-1">Adres e-mail</label>
                <input
                  name="mailbox[email]"
                  value={@mb.email}
                  type="email"
                  placeholder="sklep@hireordo.com"
                  class={input_class()}
                />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">Serwer IMAP</label>
                <input
                  name="mailbox[imap_host]"
                  value={@mb.imap_host}
                  placeholder="imap.example.pl"
                  class={input_class()}
                />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">Port</label>
                <input name="mailbox[imap_port]" value={@mb.imap_port} class={input_class()} />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">Użytkownik</label>
                <input
                  name="mailbox[username]"
                  value={@mb.username}
                  placeholder="pełny adres e-mail"
                  class={input_class()}
                />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">Hasło</label>
                <input
                  name="mailbox[password]"
                  type="password"
                  autocomplete="off"
                  placeholder="••••••••"
                  class={input_class()}
                />
              </div>
              <div class="sm:col-span-2 flex items-center gap-3 mt-1">
                <button
                  type="submit"
                  class="bg-ink text-white font-mono text-sm px-4 py-2 hover:bg-ink-soft focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
                >
                  {if @mb.id, do: "Zapisz zmiany", else: "Dodaj skrzynkę"}
                </button>
                <button
                  :if={@mb.id}
                  type="button"
                  phx-click="cancel_edit"
                  class="text-sm text-ink-mute hover:text-ink px-2"
                >
                  Anuluj edycję
                </button>
              </div>
            </form>
            <p class="text-[12px] text-ink-mute mt-2">
              Hasło jest szyfrowane w bazie. Przy edycji zapisywane jest tylko przy podaniu nowej wartości.
            </p>
          </div>
        </section>
        
    <!-- Demo controls (demo tenant only) -->
        <section :if={@tenant.demo}>
          <h2 class="font-mono text-[11px] tracking-[0.2em] text-ink-mute mb-1">DANE DEMO</h2>
          <p class="text-sm text-ink-soft mb-4">
            Zarządzanie zawartością środowiska demonstracyjnego.
          </p>
          <div class="bg-paper-card border border-slate-200 rounded-sm divide-y divide-slate-100">
            <div class="px-4 py-3 flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium">Importuj skrzynkę</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  Wczytaj przykładowy zestaw ticketów do skrzynki.
                </p>
              </div>
              <button
                phx-click="import_mailbox"
                class="shrink-0 border border-slate-300 px-3 py-1.5 text-sm hover:bg-paper"
              >
                Importuj
              </button>
            </div>
            <div class="px-4 py-3 flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium">Scenariusze</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  Wrzuć pojedynczy e-mail jak od klienta.
                </p>
              </div>
              <div class="flex gap-2 shrink-0">
                <button
                  phx-click="simulate"
                  phx-value-who="anna"
                  class="border border-slate-300 px-3 py-1.5 text-sm hover:bg-paper"
                >
                  Anna
                </button>
                <button
                  phx-click="simulate"
                  phx-value-who="tomasz"
                  class="border border-slate-300 px-3 py-1.5 text-sm hover:bg-paper"
                >
                  Tomasz
                </button>
              </div>
            </div>
            <div class="px-4 py-3 flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium text-red-700">Wyczyść wszystkie tickety</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  Usuwa tickety demo. Tej operacji nie można cofnąć.
                </p>
              </div>
              <button
                phx-click="clear_inbox"
                data-confirm="Wyczyścić wszystkie tickety?"
                class="shrink-0 border border-red-300 text-red-700 px-3 py-1.5 text-sm hover:bg-red-50"
              >
                Wyczyść
              </button>
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
