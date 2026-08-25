defmodule OrdoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OrdoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :locale, :string, default: nil, doc: "active locale for the switcher; defaults to Gettext's"

  slot :inner_block, required: true
  slot :header_actions, doc: "optional links rendered on the right of the header bar"

  def app(assigns) do
    assigns = assign(assigns, :locale, assigns.locale || Gettext.get_locale(OrdoWeb.Gettext))

    ~H"""
    <div class="min-h-screen bg-paper text-ink font-body antialiased">
      <header class="h-14 bg-paper-card border-b-2 border-ink flex items-center px-5 gap-4">
        <a href={~p"/"} class="font-mono font-semibold tracking-[0.3em] text-base select-none">
          ORDO<span class="text-label-deep">.</span>
        </a>
        <div class="ml-auto flex items-center gap-3">
          {render_slot(@header_actions)}
          <.locale_switcher locale={@locale} />
        </div>
      </header>

      <main class="px-4 py-16 sm:px-6">
        <div class="mx-auto max-w-sm space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the signed-in user's account menu (email, account settings, log out).

  Reused in the app page headers (inbox, settings) so the account controls live
  inside each page's own header instead of a floating overlay.

  ## Examples

      <.account_menu current_scope={@current_scope} />
  """
  attr :current_scope, :map, required: true, doc: "the current scope with the signed-in user"
  attr :id, :string, default: "account-menu", doc: "id of the dropdown, unique per page"

  def account_menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        phx-click={JS.toggle(to: "##{@id}")}
        class="flex items-center gap-1.5 text-sm text-ink-soft hover:text-ink px-2 py-1.5 rounded hover:bg-paper"
      >
        <span class="font-mono text-[13px] max-w-[180px] truncate">
          {@current_scope.user.email}
        </span>
        <svg class="w-3 h-3 text-ink-mute" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div
        id={@id}
        phx-click-away={JS.hide(to: "##{@id}")}
        class="hidden absolute top-full right-0 mt-1 w-52 bg-paper-card border border-slate-200 shadow-lg rounded-sm py-1 z-40"
      >
        <.link navigate={~p"/users/settings"} class="block px-4 py-2 text-sm hover:bg-paper">
          Ustawienia konta
        </.link>
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="block px-4 py-2 text-sm text-red-700 hover:bg-paper"
        >
          Wyloguj
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact language switcher (PL / EN). Each link is a full navigation
  to `/locale/:locale`, which stores the choice in the session and returns here.

  ## Examples

      <.locale_switcher locale={@locale} />
  """
  attr :locale, :string, required: true, doc: "the currently active locale"

  def locale_switcher(assigns) do
    assigns = assign(assigns, :locales, OrdoWeb.Locale.supported())

    ~H"""
    <div class="flex items-center gap-1 font-mono text-xs">
      <%= for {loc, i} <- Enum.with_index(@locales) do %>
        <span :if={i > 0} class="text-slate-300">/</span>
        <.link
          href={~p"/locale/#{loc}"}
          class={[
            "uppercase px-1 py-0.5 rounded transition-colors",
            (loc == @locale && "text-ink font-semibold") || "text-ink-mute hover:text-ink"
          ]}
        >
          {loc}
        </.link>
      <% end %>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
