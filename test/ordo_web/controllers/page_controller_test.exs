defmodule OrdoWeb.PageControllerTest do
  use OrdoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "resolves your store"
  end
end
