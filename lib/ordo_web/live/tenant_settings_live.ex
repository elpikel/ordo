defmodule OrdoWeb.TenantSettingsLive do
  @moduledoc "Per-tenant setup: BaseLinker token + mailboxes. NOTE: no auth yet."
  use OrdoWeb, :live_view

  alias Ordo.{Mailboxes, Support}

  @impl true
  def mount(%{"tenant" => param}, _session, socket) do
    tenant = Support.fetch_tenant!(param)

    {:ok,
     assign(socket,
       tenant: tenant,
       mailboxes: Mailboxes.list_for_tenant(tenant.id),
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
        {:noreply, socket |> assign(tenant: tenant) |> notice("Token BaseLinker zapisany.")}
    end
  end

  def handle_event("add_mailbox", %{"mailbox" => params}, socket) do
    attrs = Map.put(params, "tenant_id", socket.assigns.tenant.id)

    case Mailboxes.create(attrs) do
      {:ok, _} -> {:noreply, socket |> reload() |> notice("Skrzynka dodana.")}
      {:error, cs} -> {:noreply, notice(socket, "Błąd: #{errors(cs)}")}
    end
  end

  def handle_event("delete_mailbox", %{"id" => id}, socket) do
    Mailboxes.delete!(id)
    {:noreply, socket |> reload() |> notice("Skrzynka usunięta.")}
  end

  def handle_event("toggle_mailbox", %{"id" => id, "active" => active}, socket) do
    Mailboxes.set_active(id, active != "true")
    {:noreply, reload(socket)}
  end

  defp reload(socket), do: assign(socket, mailboxes: Mailboxes.list_for_tenant(socket.assigns.tenant.id))
  defp notice(socket, msg), do: assign(socket, notice: msg)

  defp errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-paper text-ink font-body">
      <header class="max-w-4xl mx-auto px-5 sm:px-8 py-5 flex items-center justify-between">
        <div class="font-mono font-medium tracking-[0.35em] text-lg select-none">
          ORDO<span class="text-label-deep">.</span>
          <span class="ml-3 font-body font-normal text-xs text-ink-mute tracking-normal">
            {@tenant.name} · ustawienia
          </span>
        </div>
        <.link navigate={~p"/#{@tenant.slug}/inbox"} class="font-mono text-sm border border-ink px-3 py-2 hover:bg-ink hover:text-paper transition-colors">
          ← Skrzynka
        </.link>
      </header>
      <div class="perf max-w-4xl mx-auto"></div>

      <div class="max-w-4xl mx-auto px-5 sm:px-8 pt-8 pb-16 space-y-8">
        <p :if={@notice} class="font-mono text-sm text-okay border border-okay bg-paper-card px-4 py-2">
          {@notice}
        </p>

        <!-- BaseLinker -->
        <section class="bg-paper-card border border-slate-300 shadow-[6px_6px_0_0_#16233B14] p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="font-display font-bold text-xl">BaseLinker</h2>
            <span class={["font-mono text-xs px-2 py-1 border", (@tenant.bl_token && "text-okay border-okay") || "text-ink-mute border-slate-400"]}>
              {if @tenant.bl_token, do: "skonfigurowany", else: "brak tokenu"}
            </span>
          </div>
          <form phx-submit="save_baselinker" class="flex flex-col sm:flex-row gap-3">
            <input type="password" name="token" autocomplete="off" placeholder="Wklej token BaseLinker (X-BLToken)"
                   class="flex-1 border border-ink bg-paper px-3 py-2 font-mono text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-label" />
            <button type="submit" class="bg-ink text-paper font-mono text-sm px-5 py-2 hover:bg-ink-soft transition-colors">
              Zapisz token
            </button>
          </form>
          <p class="text-xs text-ink-mute mt-2">Token jest szyfrowany w bazie. Zapisywany jest tylko przy podaniu nowej wartości.</p>
        </section>

        <!-- Mailboxes -->
        <section class="bg-paper-card border border-slate-300 shadow-[6px_6px_0_0_#16233B14] p-6">
          <h2 class="font-display font-bold text-xl mb-4">Skrzynki e-mail</h2>

          <table :if={@mailboxes != []} class="w-full text-sm mb-6">
            <thead>
              <tr class="text-left font-mono text-[11px] tracking-wider text-ink-mute uppercase border-b border-slate-200">
                <th class="py-2">E-mail</th><th>IMAP</th><th>Status</th><th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={m <- @mailboxes} class="border-b border-slate-100">
                <td class="py-2">{m.email}</td>
                <td class="font-mono text-xs text-ink-mute">{m.imap_host}:{m.imap_port}</td>
                <td>
                  <button phx-click="toggle_mailbox" phx-value-id={m.id} phx-value-active={to_string(m.active)}
                          class={["font-mono text-[11px] px-2 py-0.5 border", (m.active && "text-okay border-okay") || "text-ink-mute border-slate-400"]}>
                    {if m.active, do: "aktywna", else: "wyłączona"}
                  </button>
                </td>
                <td class="text-right">
                  <button phx-click="delete_mailbox" phx-value-id={m.id} data-confirm="Usunąć skrzynkę?"
                          class="font-mono text-xs text-ink-mute hover:text-ink">usuń</button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@mailboxes == []} class="text-sm text-ink-mute mb-6">Brak skrzynek. Dodaj pierwszą poniżej.</p>

          <form phx-submit="add_mailbox" class="grid sm:grid-cols-2 gap-3">
            <input name="mailbox[email]" placeholder="adres e-mail (bok@sklep.pl)" class={input_class()} />
            <input name="mailbox[username]" placeholder="login IMAP (zwykle e-mail)" class={input_class()} />
            <input name="mailbox[imap_host]" placeholder="host IMAP (imap.gmail.com)" class={input_class()} />
            <input name="mailbox[imap_port]" value="993" placeholder="port IMAP" class={input_class()} />
            <input type="password" name="mailbox[password]" autocomplete="off" placeholder="hasło / hasło aplikacji" class={input_class()} />
            <input name="mailbox[smtp_host]" placeholder="host SMTP (smtp.gmail.com)" class={input_class()} />
            <input name="mailbox[smtp_port]" value="587" placeholder="port SMTP" class={input_class()} />
            <div class="sm:col-span-2">
              <button type="submit" class="bg-ink text-paper font-mono text-sm px-5 py-2 hover:bg-ink-soft transition-colors">
                Dodaj skrzynkę
              </button>
            </div>
          </form>
          <p class="text-xs text-ink-mute mt-2">Hasło jest szyfrowane w bazie. Ordo pobiera pocztę z INBOX co minutę.</p>
        </section>
      </div>
    </div>
    """
  end

  defp input_class,
    do: "border border-slate-300 bg-paper px-3 py-2 text-sm font-mono focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
end
