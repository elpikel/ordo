defmodule OrdoWeb.PageControllerTest do
  use OrdoWeb.ConnCase

  import Swoosh.TestAssertions

  alias Ordo.Leads.PilotRequest
  alias Ordo.Repo

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

  describe "POST /pilot" do
    test "saves the email, notifies the team, and confirms to the visitor", %{conn: conn} do
      conn = post(conn, ~p"/pilot", pilot_request: %{email: "store@example.pl"})

      assert redirected_to(conn) == "/?pilot=sent#early-access"

      assert %PilotRequest{email: "store@example.pl"} = Repo.get_by(PilotRequest, email: "store@example.pl")

      assert_email_sent(fn email ->
        assert Enum.any?(email.to, fn {_name, address} -> address == "hello@hireordo.com" end)
        assert email.subject =~ "store@example.pl"
      end)
    end

    test "replies with JSON (no redirect) for a fetch request", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-requested-with", "fetch")
        |> post(~p"/pilot", pilot_request: %{email: "store@example.pl"})

      assert json_response(conn, 200) == %{"status" => "sent"}
      assert Repo.get_by(PilotRequest, email: "store@example.pl")

      assert_email_sent(fn email ->
        assert Enum.any?(email.to, fn {_name, address} -> address == "hello@hireordo.com" end)
      end)
    end

    test "replies with 422 JSON for an invalid fetch request", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-requested-with", "fetch")
        |> post(~p"/pilot", pilot_request: %{email: "not-an-email"})

      assert json_response(conn, 422) == %{"status" => "error"}
      assert Repo.aggregate(PilotRequest, :count) == 0
      assert_no_email_sent()
    end

    test "rejects an invalid email without notifying the team", %{conn: conn} do
      conn = post(conn, ~p"/pilot", pilot_request: %{email: "not-an-email"})

      assert redirected_to(conn) == "/?pilot=error#early-access"
      assert Repo.aggregate(PilotRequest, :count) == 0
      assert_no_email_sent()
    end

    test "handles a missing email param", %{conn: conn} do
      conn = post(conn, ~p"/pilot", %{})
      assert redirected_to(conn) == "/?pilot=error#early-access"
    end
  end
end
