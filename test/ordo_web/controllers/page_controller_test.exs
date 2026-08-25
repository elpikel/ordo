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
end
