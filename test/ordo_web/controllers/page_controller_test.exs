defmodule OrdoWeb.PageControllerTest do
  use OrdoWeb.ConnCase

  test "GET / renders the landing page in Polish by default", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Zatrudnij Ordo"
  end

  test "GET / renders in English when the browser prefers it", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "en-US,en;q=0.9")
      |> get(~p"/")

    assert html_response(conn, 200) =~ "Hire Ordo"
  end

  test "GET / points anonymous visitors at registration and login", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~p"/users/register"
    assert html =~ ~p"/users/log-in"
  end

  test "GET / sends a logged-in visitor to the app instead of registration", %{conn: conn} do
    conn = conn |> log_in_user(Ordo.AccountsFixtures.user_fixture()) |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ ~p"/inbox"
    assert html =~ "Przejdź do Ordo"
    refute html =~ ~p"/users/register"
  end
end
