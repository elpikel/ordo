defmodule OrdoWeb.GoogleOAuthControllerTest do
  use OrdoWeb.ConnCase, async: false

  alias Ordo.Channels
  alias Ordo.Channels.Gbp.HTTP

  setup :register_and_log_in_user

  setup do
    Application.put_env(:ordo, :gbp_req_options, plug: {Req.Test, __MODULE__}, retry: false)
    Application.put_env(:ordo, HTTP, client_id: "app-id", client_secret: "app-secret")

    on_exit(fn ->
      Application.delete_env(:ordo, :gbp_req_options)
      Application.delete_env(:ordo, HTTP)
    end)

    :ok
  end

  describe "authorize" do
    test "redirects to Google's consent screen and stashes state", %{conn: conn} do
      conn = get(conn, ~p"/oauth/google/authorize")

      assert redirected_to(conn) =~ "accounts.google.com/o/oauth2/v2/auth"
      assert get_session(conn, :gbp_oauth_state)
    end

    test "without app credentials, flashes and returns to settings", %{conn: conn} do
      Application.delete_env(:ordo, HTTP)
      conn = get(conn, ~p"/oauth/google/authorize")

      assert redirected_to(conn) == ~p"/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end
  end

  describe "callback" do
    test "exchanges the code, discovers the profile, and connects a gbp channel", %{conn: conn, scope: scope} do
      Req.Test.stub(__MODULE__, fn c ->
        cond do
          c.request_path == "/token" ->
            Req.Test.json(c, %{"refresh_token" => "refresh-xyz", "access_token" => "access-xyz"})

          String.ends_with?(c.request_path, "/v1/accounts") ->
            Req.Test.json(c, %{"accounts" => [%{"name" => "accounts/123"}]})

          String.ends_with?(c.request_path, "/locations") ->
            Req.Test.json(c, %{"locations" => [%{"name" => "locations/456"}]})

          true ->
            Req.Test.json(c, %{})
        end
      end)

      conn =
        conn
        |> init_test_session(%{gbp_oauth_state: "st-1"})
        |> get(~p"/oauth/google/callback?code=the-code&state=st-1")

      assert redirected_to(conn) == ~p"/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info)

      assert [channel] = Channels.gbp_channels(scope.tenant.id)
      assert channel.password == "refresh-xyz"
      assert channel.config == %{"account" => "accounts/123", "location" => "locations/456"}
    end

    test "rejects a mismatched state (CSRF guard)", %{conn: conn, scope: scope} do
      conn =
        conn
        |> init_test_session(%{gbp_oauth_state: "expected"})
        |> get(~p"/oauth/google/callback?code=the-code&state=forged")

      assert redirected_to(conn) == ~p"/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Channels.gbp_channels(scope.tenant.id) == []
    end

    test "handles the operator declining consent", %{conn: conn} do
      conn = get(conn, ~p"/oauth/google/callback?error=access_denied")

      assert redirected_to(conn) == ~p"/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end
  end
end
