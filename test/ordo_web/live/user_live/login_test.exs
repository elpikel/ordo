defmodule OrdoWeb.UserLive.LoginTest do
  use OrdoWeb.ConnCase, async: true

  import Ordo.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Zaloguj się"
      assert html =~ "link do logowania"
      assert html =~ "Zaloguj przez e-mail"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        lv
        |> form("#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Jeśli Twój adres jest w naszym systemie"

      assert Ordo.Repo.get_by!(Ordo.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        lv
        |> form("#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Jeśli Twój adres jest w naszym systemie"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = set_password(user_fixture())

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: user.email, password: valid_user_password(), remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/inbox"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Nieprawidłowy e-mail lub hasło"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Zaloguj się ponownie"
      refute html =~ "Register"
      assert html =~ "Zaloguj przez e-mail"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end
  end
end
