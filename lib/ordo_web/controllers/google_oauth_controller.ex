defmodule OrdoWeb.GoogleOAuthController do
  @moduledoc """
  Google Business Profile connect flow (see ADR-0012). `authorize` redirects the
  operator to Google's consent screen; `callback` exchanges the code, discovers
  the profile, and upserts a `gbp` channel on the current tenant. A random
  `state` in the session guards against CSRF on the callback.
  """
  use OrdoWeb, :controller

  alias Ordo.Channels
  alias Ordo.Channels.Gbp.OAuth

  require Logger

  def authorize(conn, _params) do
    if OAuth.configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

      conn
      |> put_session(:gbp_oauth_state, state)
      |> redirect(external: OAuth.authorize_url(callback_url(conn), state))
    else
      conn
      |> put_flash(:error, gettext("Google Business Profile is not configured."))
      |> redirect(to: ~p"/settings")
    end
  end

  # The operator declined consent (or Google returned an error).
  def callback(conn, %{"error" => _}), do: fail(conn, gettext("Google connection was cancelled."))

  def callback(conn, %{"code" => code, "state" => state}) do
    tenant = conn.assigns.current_scope.tenant

    with :ok <- verify_state(conn, state),
         {:ok, %{refresh_token: refresh, access_token: access}} <- OAuth.exchange_code(code, callback_url(conn)),
         {:ok, %{account: account, location: location}} <- OAuth.discover_profile(access),
         attrs = %{name: "Google", password: refresh, config: %{"account" => account, "location" => location}},
         {:ok, _channel} <- Channels.upsert_gbp_channel(tenant.id, account, attrs) do
      conn
      |> delete_session(:gbp_oauth_state)
      |> put_flash(:info, gettext("Google Business Profile connected."))
      |> redirect(to: ~p"/settings")
    else
      {:error, reason} ->
        Logger.warning("GBP OAuth callback failed: #{inspect(reason)}")
        fail(conn, gettext("Could not connect Google Business Profile. Please try again."))
    end
  end

  def callback(conn, _params), do: fail(conn, gettext("Invalid response from Google."))

  defp verify_state(conn, state) do
    if is_binary(state) and state != "" and get_session(conn, :gbp_oauth_state) == state,
      do: :ok,
      else: {:error, :bad_state}
  end

  defp fail(conn, message) do
    conn
    |> delete_session(:gbp_oauth_state)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/settings")
  end

  defp callback_url(conn), do: url(conn, ~p"/oauth/google/callback")
end
