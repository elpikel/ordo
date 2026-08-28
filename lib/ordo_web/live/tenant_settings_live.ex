defmodule OrdoWeb.TenantSettingsLive do
  @moduledoc "Per-tenant setup: BaseLinker token + channels (+ demo controls). Tenant comes from current_scope."
  use OrdoWeb, :live_view

  alias Ordo.Channels
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
       channels: Channels.list_for_tenant(tenant.id),
       editing_token: false,
       mb: @blank_mb,
       notice: nil,
       page_title: "Ordo — #{tenant.name} · " <> gettext("settings")
     )}
  end

  @impl true
  def handle_event("save_baselinker", %{"token" => token}, socket) do
    case String.trim(token) do
      "" ->
        {:noreply, notice(socket, gettext("Enter a token."))}

      token ->
        {:ok, tenant} = Support.update_tenant(socket.assigns.tenant, %{bl_token: token})
        {:noreply, socket |> assign(tenant: tenant, editing_token: false) |> notice(gettext("BaseLinker token saved."))}
    end
  end

  def handle_event("change_token", _params, socket), do: {:noreply, assign(socket, editing_token: true)}
  def handle_event("cancel_token", _params, socket), do: {:noreply, assign(socket, editing_token: false)}

  def handle_event("submit_mailbox", %{"mailbox" => params}, socket) do
    mb = socket.assigns.mb

    result =
      if mb.id do
        Channels.update(Channels.get!(mb.id), drop_blank_password(params))
      else
        params |> Map.put("tenant_id", socket.assigns.tenant.id) |> Map.put("type", "email") |> Channels.create()
      end

    case result do
      {:ok, _} -> {:noreply, socket |> reload() |> assign(mb: @blank_mb) |> notice(gettext("Mailbox saved."))}
      {:error, cs} -> {:noreply, notice(socket, gettext("Error: %{errors}", errors: errors(cs)))}
    end
  end

  def handle_event("edit_mailbox", %{"id" => id}, socket) do
    m = Channels.get!(id)

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

  def handle_event("delete_channel", %{"id" => id}, socket) do
    Channels.delete!(id)
    {:noreply, socket |> reload() |> assign(mb: @blank_mb) |> notice(gettext("Channel removed."))}
  end

  def handle_event("save_notifications", %{"notify" => params}, socket) do
    attrs = %{
      notify_enabled: params["enabled"] == "true",
      notify_whatsapp: String.trim(params["whatsapp"] || "")
    }

    case Support.update_tenant(socket.assigns.tenant, attrs) do
      {:ok, tenant} -> {:noreply, socket |> assign(tenant: tenant) |> notice(gettext("Notification settings saved."))}
      {:error, cs} -> {:noreply, notice(socket, gettext("Error: %{errors}", errors: errors(cs)))}
    end
  end

  def handle_event("import_mailbox", _params, socket) do
    Support.import_demo_mailbox!(socket.assigns.tenant)
    {:noreply, notice(socket, gettext("Importing mailbox — open the mailbox to see it."))}
  end

  def handle_event("import_reviews", _params, socket) do
    Support.import_demo_reviews!(socket.assigns.tenant)
    {:noreply, notice(socket, gettext("Importing Google reviews — open the inbox to see them."))}
  end

  def handle_event("clear_inbox", _params, socket) do
    Support.clear_inbox!(socket.assigns.tenant.id)
    {:noreply, notice(socket, gettext("Tickets cleared."))}
  end

  def handle_event("simulate", %{"who" => who}, socket) do
    Support.receive_email(socket.assigns.tenant.id, @presets[who])
    {:noreply, notice(socket, gettext("Email generated — open the mailbox."))}
  end

  defp reload(socket), do: assign(socket, channels: Channels.list_for_tenant(socket.assigns.tenant.id))
  defp notice(socket, msg), do: assign(socket, notice: msg)

  defp drop_blank_password(params) do
    if String.trim(params["password"] || "") == "", do: Map.delete(params, "password"), else: params
  end

  defp errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp mask(token) when is_binary(token) and byte_size(token) >= 4, do: "••••••••••••" <> String.slice(token, -4, 4)

  defp mask(_), do: "••••••••••••"

  defp channel_kind_label(%{type: "gbp"}), do: gettext("GOOGLE")
  defp channel_kind_label(_), do: gettext("EMAIL")

  defp channel_identity(%{type: "gbp"} = c), do: c.name || gettext("Google Business Profile")
  defp channel_identity(c), do: c.email

  defp channel_status(%{type: "gbp"} = c) do
    if c.last_error == Channels.gbp_auth_error(),
      do: {gettext("RECONNECT"), "border-red-300 text-red-700"},
      else: {gettext("CONNECTED"), "border-okay text-okay"}
  end

  defp channel_status(c) do
    cond do
      c.last_error -> {gettext("LOGIN ERROR"), "border-red-300 text-red-700"}
      c.active -> {gettext("ACTIVE"), "border-okay text-okay"}
      true -> {gettext("DISABLED"), "border-slate-300 text-ink-mute"}
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
        <span class="text-sm text-ink-soft">{@tenant.name} · {gettext("settings")}</span>
        <.link
          navigate={~p"/inbox"}
          class="ml-auto flex items-center gap-1.5 text-sm text-ink-soft hover:text-ink px-3 py-1.5 rounded hover:bg-paper"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
          {gettext("Back to mailbox")}
        </.link>
        <span class="w-px h-5 bg-slate-200 mx-1"></span>
        <Layouts.locale_switcher locale={@locale} />
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
            {gettext(
              "The API token connects Ordo with your store's orders, shipments and documents. You can generate it in the BaseLinker panel: My account → API."
            )}
          </p>

          <div
            :if={!@tenant.bl_token || @editing_token}
            class="bg-paper-card border border-slate-200 rounded-sm px-4 py-4"
          >
            <div class="flex items-center gap-2 mb-3">
              <span class="font-mono text-[10px] px-2 py-0.5 border border-slate-300 text-ink-mute">
                {gettext("NO TOKEN")}
              </span>
              <span class="text-[12px] text-ink-mute">
                {gettext("BaseLinker connection inactive")}
              </span>
            </div>
            <form phx-submit="save_baselinker" class="flex gap-2">
              <input
                type="password"
                name="token"
                autocomplete="off"
                placeholder={gettext("paste API token…")}
                class={input_class()}
              />
              <button
                type="submit"
                class="bg-ink text-white font-mono text-sm px-4 py-2 hover:bg-ink-soft focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
              >
                {gettext("Save token")}
              </button>
              <button
                :if={@editing_token}
                type="button"
                phx-click="cancel_token"
                class="text-sm text-ink-mute hover:text-ink px-2"
              >
                {gettext("Cancel")}
              </button>
            </form>
            <p class="text-[12px] text-ink-mute mt-2">
              {gettext("The token is encrypted in the database and is never shown again.")}
            </p>
          </div>

          <div
            :if={@tenant.bl_token && !@editing_token}
            class="bg-paper-card border border-slate-200 rounded-sm px-4 py-4"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class="font-mono text-[10px] px-2 py-0.5 border border-okay text-okay">
                  {gettext("CONNECTED")}
                </span>
                <span class="font-mono text-sm text-ink-mute">
                  {gettext("token")} {mask(@tenant.bl_token)}
                </span>
              </div>
              <button
                phx-click="change_token"
                class="text-sm text-ink-soft hover:text-ink border border-slate-300 px-3 py-1 hover:bg-paper"
              >
                {gettext("Change token")}
              </button>
            </div>
            <p class="text-[12px] text-ink-mute mt-2">
              {gettext("A new token is saved only when a new value is provided.")}
            </p>
          </div>
        </section>
        
    <!-- Channels -->
        <section>
          <h2 class="font-mono text-[11px] tracking-[0.2em] text-ink-mute mb-1">
            {gettext("CHANNELS")}
          </h2>
          <p class="text-sm text-ink-soft mb-4">
            {gettext(
              "Everywhere Ordo hears from customers — email mailboxes and your Google Business Profile — feeding one inbox."
            )}
          </p>

          <div
            :if={@channels != []}
            class="bg-paper-card border border-slate-200 rounded-sm divide-y divide-slate-100"
          >
            <div :for={c <- @channels} class="px-4 py-3 flex items-center justify-between gap-4">
              <div class="min-w-0 flex items-center gap-2">
                <span class="font-mono text-[10px] px-1.5 py-0.5 border border-slate-300 text-ink-mute shrink-0">
                  {channel_kind_label(c)}
                </span>
                <div class="min-w-0">
                  <p class="font-mono text-sm truncate">{channel_identity(c)}</p>
                  <p :if={c.type == "email"} class="text-[12px] text-ink-mute mt-0.5">
                    {c.imap_host}:{c.imap_port}
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <% {label, cls} = channel_status(c) %>
                <span class={["font-mono text-[10px] px-2 py-0.5 border", cls]}>{label}</span>
                <button
                  :if={c.type == "email"}
                  phx-click="edit_mailbox"
                  phx-value-id={c.id}
                  class="text-sm text-ink-soft hover:text-ink border border-slate-300 px-3 py-1 hover:bg-paper"
                >
                  {gettext("Edit")}
                </button>
                <.link
                  :if={c.type == "gbp" and c.last_error == Channels.gbp_auth_error()}
                  href={~p"/oauth/google/authorize"}
                  class="text-sm text-white bg-ink hover:bg-ink-soft px-3 py-1"
                >
                  {gettext("Reconnect")}
                </.link>
                <button
                  phx-click="delete_channel"
                  phx-value-id={c.id}
                  data-confirm={
                    if c.type == "gbp",
                      do: gettext("Disconnect Google Business Profile?"),
                      else: gettext("Delete mailbox %{email}?", email: c.email)
                  }
                  class="text-sm text-red-700 border border-red-300 px-3 py-1 hover:bg-red-50"
                >
                  {if c.type == "gbp", do: gettext("Disconnect"), else: gettext("Delete")}
                </button>
              </div>
            </div>
          </div>
          <div
            :if={@channels == []}
            class="bg-paper-card border border-dashed border-slate-300 rounded-sm px-4 py-8 text-center"
          >
            <p class="text-sm text-ink-mute">{gettext("No channels yet. Connect one below.")}</p>
          </div>
          
    <!-- Connect Google Business Profile (a tenant can connect several) -->
          <div class="mt-4 bg-paper-card border border-slate-200 rounded-sm px-4 py-4 flex items-center justify-between gap-4">
            <div>
              <p class="text-sm font-semibold">{gettext("Google Business Profile")}</p>
              <p class="text-[12px] text-ink-mute mt-0.5">
                {gettext(
                  "Connect a Google profile to answer its reviews straight from the inbox. Add as many as you manage."
                )}
              </p>
            </div>
            <.link
              href={~p"/oauth/google/authorize"}
              class="shrink-0 bg-ink text-white font-mono text-sm px-4 py-2 hover:bg-ink-soft focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
            >
              {gettext("Connect")}
            </.link>
          </div>
          
    <!-- Add / edit email mailbox -->
          <div class="mt-4 bg-paper-card border border-slate-200 rounded-sm px-4 py-4">
            <p class="text-sm font-semibold mb-3">
              {if @mb.id,
                do: gettext("Edit mailbox: %{email}", email: @mb.email),
                else: gettext("Add email mailbox")}
            </p>
            <form phx-submit="submit_mailbox" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div class="sm:col-span-2">
                <label class="block text-[12px] text-ink-mute mb-1">{gettext("Email address")}</label>
                <input
                  name="mailbox[email]"
                  value={@mb.email}
                  type="email"
                  placeholder="sklep@hireordo.com"
                  class={input_class()}
                />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">{gettext("IMAP server")}</label>
                <input
                  name="mailbox[imap_host]"
                  value={@mb.imap_host}
                  placeholder="imap.example.pl"
                  class={input_class()}
                />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">{gettext("Port")}</label>
                <input name="mailbox[imap_port]" value={@mb.imap_port} class={input_class()} />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">{gettext("Username")}</label>
                <input
                  name="mailbox[username]"
                  value={@mb.username}
                  placeholder={gettext("full email address")}
                  class={input_class()}
                />
              </div>
              <div>
                <label class="block text-[12px] text-ink-mute mb-1">{gettext("Password")}</label>
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
                  {if @mb.id, do: gettext("Save changes"), else: gettext("Add mailbox")}
                </button>
                <button
                  :if={@mb.id}
                  type="button"
                  phx-click="cancel_edit"
                  class="text-sm text-ink-mute hover:text-ink px-2"
                >
                  {gettext("Cancel editing")}
                </button>
              </div>
            </form>
            <p class="text-[12px] text-ink-mute mt-2">
              {gettext(
                "The password is encrypted in the database. When editing, it is saved only when a new value is provided."
              )}
            </p>
          </div>
        </section>
        
    <!-- Notifications -->
        <section>
          <h2 class="font-mono text-[11px] tracking-[0.2em] text-ink-mute mb-1">
            {gettext("NOTIFICATIONS")}
          </h2>
          <p class="text-sm text-ink-soft mb-4">
            {gettext(
              "Get pinged when a new message has a draft ready — with the original message and the proposed reply — so you can approve it from your email or WhatsApp."
            )}
          </p>

          <form
            phx-submit="save_notifications"
            class="bg-paper-card border border-slate-200 rounded-sm px-4 py-4 space-y-4"
          >
            <label class="flex items-start gap-3 cursor-pointer">
              <input type="hidden" name="notify[enabled]" value="false" />
              <input
                type="checkbox"
                name="notify[enabled]"
                value="true"
                checked={@tenant.notify_enabled}
                class="mt-0.5 h-4 w-4 border-slate-300 text-ink focus:ring-label"
              />
              <span>
                <span class="text-sm font-medium">
                  {gettext("Notify me about incoming messages")}
                </span>
                <span class="block text-[12px] text-ink-mute mt-0.5">
                  {gettext("Emails every teammate on this account. Off by default.")}
                </span>
              </span>
            </label>

            <div>
              <label class="block text-[12px] text-ink-mute mb-1">
                {gettext("WhatsApp number (optional)")}
              </label>
              <input
                name="notify[whatsapp]"
                value={@tenant.notify_whatsapp}
                placeholder="+48 600 100 200"
                class={input_class()}
              />
              <p class="text-[12px] text-ink-mute mt-1">
                {gettext("Also send a WhatsApp you can approve by replying OK. Leave blank to skip.")}
              </p>
            </div>

            <button
              type="submit"
              class="bg-ink text-white font-mono text-sm px-4 py-2 hover:bg-ink-soft focus:outline-none focus-visible:ring-2 focus-visible:ring-label"
            >
              {gettext("Save")}
            </button>
          </form>
        </section>
        
    <!-- Demo controls (demo tenant only) -->
        <section :if={@tenant.demo}>
          <h2 class="font-mono text-[11px] tracking-[0.2em] text-ink-mute mb-1">
            {gettext("DEMO DATA")}
          </h2>
          <p class="text-sm text-ink-soft mb-4">
            {gettext("Manage the contents of the demo environment.")}
          </p>
          <div class="bg-paper-card border border-slate-200 rounded-sm divide-y divide-slate-100">
            <div class="px-4 py-3 flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium">{gettext("Import mailbox")}</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  {gettext("Load a sample set of tickets into the mailbox.")}
                </p>
              </div>
              <button
                phx-click="import_mailbox"
                class="shrink-0 border border-slate-300 px-3 py-1.5 text-sm hover:bg-paper"
              >
                {gettext("Import")}
              </button>
            </div>
            <div class="px-4 py-3 flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium">{gettext("Import Google reviews")}</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  {gettext("Load sample Google Business Profile reviews into the inbox.")}
                </p>
              </div>
              <button
                phx-click="import_reviews"
                class="shrink-0 border border-slate-300 px-3 py-1.5 text-sm hover:bg-paper"
              >
                {gettext("Import")}
              </button>
            </div>
            <div class="px-4 py-3 flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium">{gettext("Scenarios")}</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  {gettext("Drop in a single email as if from a customer.")}
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
                <p class="text-sm font-medium text-red-700">{gettext("Clear all tickets")}</p>
                <p class="text-[12px] text-ink-mute mt-0.5">
                  {gettext("Deletes demo tickets. This operation cannot be undone.")}
                </p>
              </div>
              <button
                phx-click="clear_inbox"
                data-confirm={gettext("Clear all tickets?")}
                class="shrink-0 border border-red-300 text-red-700 px-3 py-1.5 text-sm hover:bg-red-50"
              >
                {gettext("Clear")}
              </button>
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
