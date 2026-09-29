defmodule OrdoWeb.UserLive.Registration do
  @moduledoc false
  use OrdoWeb, :live_view

  alias Ordo.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>{gettext("Create your account")}</p>
            <:subtitle>
              {gettext(
                "Tell us your store name and email — we'll send you a link to get started, no password needed."
              )}
            </:subtitle>
          </.header>
        </div>

        <.form
          :let={f}
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
        >
          <.input
            field={f[:name]}
            type="text"
            label={gettext("Store name")}
            autocomplete="organization"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" class="w-full">
            {gettext("Create account")} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <p class="text-center text-sm text-ink-soft">
          {gettext("Already have an account?")}
          <.link navigate={~p"/users/log-in"} class="font-semibold underline">
            {gettext("Log in")}
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, to_form(%{}, as: "user"))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: "user"))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.register_owner(params) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Account created! Check your email for a link to log in and finish setup.")
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, error_form(params, changeset))}
    end
  end

  # Registration spans two schemas (a tenant, then a user), so an error can come
  # back as either changeset. Re-render the submitted params and surface the
  # relevant field errors — a missing store name (:name) or a taken email
  # (:email) — inline on the matching input.
  defp error_form(params, changeset) do
    errors = Enum.filter(changeset.errors, fn {field, _} -> field in [:name, :email] end)
    to_form(params, as: "user", errors: errors)
  end
end
