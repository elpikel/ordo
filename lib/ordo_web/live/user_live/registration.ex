defmodule OrdoWeb.UserLive.Registration do
  @moduledoc false
  use OrdoWeb, :live_view

  alias Ordo.Accounts
  alias Ordo.Accounts.User

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
                "Enter your email and we'll send you a link to get started — no password needed."
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
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
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
    changeset = Accounts.change_user_email(%User{})
    {:ok, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_email(%User{}, params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
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
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end
end
