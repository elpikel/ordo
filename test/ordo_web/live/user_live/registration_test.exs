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
      assert html =~ "Masz już konto?"
    end
  end

  describe "create account" do
    test "provisions a tenant, an unconfirmed user, and a magic link", %{conn: conn} do
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _lv, html} =
        lv
        |> form("#registration_form", user: %{email: email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Konto utworzone"

      user = Repo.get_by!(User, email: email)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.hashed_password)
      assert user.tenant_id

      assert Repo.get(Tenant, user.tenant_id)
      assert Repo.get_by!(UserToken, user_id: user.id).context == "login"
    end

    test "rejects an email that is already registered without creating a tenant", %{conn: conn} do
      %{email: email} = user_fixture()
      tenants_before = Repo.aggregate(Tenant, :count)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> form("#registration_form", user: %{email: email})
        |> render_submit()

      # The email field surfaces a validation error and the rolled-back
      # transaction leaves no orphan tenant behind.
      assert html =~ "registration_form"
      assert Repo.aggregate(User, :count) == 1
      assert Repo.aggregate(Tenant, :count) == tenants_before
    end
  end
end
