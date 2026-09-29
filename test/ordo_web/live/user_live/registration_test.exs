defmodule OrdoWeb.UserLive.RegistrationTest do
  use OrdoWeb.ConnCase, async: true

  import Ordo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Ordo.Accounts.User
  alias Ordo.Accounts.UserToken
  alias Ordo.Repo
  alias Ordo.Support.Tenant

  describe "registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Załóż konto"
      assert html =~ "Nazwa sklepu"
      assert html =~ "Masz już konto?"
    end
  end

  describe "create account" do
    test "provisions the named tenant, an unconfirmed user, and a magic link", %{conn: conn} do
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _lv, html} =
        lv
        |> form("#registration_form", user: %{name: "Acme Store", email: email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Konto utworzone"

      user = Repo.get_by!(User, email: email)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.hashed_password)

      tenant = Repo.get!(Tenant, user.tenant_id)
      assert tenant.name == "Acme Store"

      assert Repo.get_by!(UserToken, user_id: user.id).context == "login"
    end

    test "allows two stores to share the same name", %{conn: conn} do
      tenant_fixture(name: "Acme Store")

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      {:ok, _lv, _html} =
        lv
        |> form("#registration_form", user: %{name: "Acme Store", email: email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      user = Repo.get_by!(User, email: email)
      assert Repo.get!(Tenant, user.tenant_id).name == "Acme Store"
    end

    test "rejects an email that is already registered without creating a tenant", %{conn: conn} do
      %{email: email} = user_fixture()
      tenants_before = Repo.aggregate(Tenant, :count)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> form("#registration_form", user: %{name: "Fresh Store", email: email})
        |> render_submit()

      assert html =~ "jest już zajęte"
      assert Repo.aggregate(User, :count) == 1
      assert Repo.aggregate(Tenant, :count) == tenants_before
    end
  end
end
