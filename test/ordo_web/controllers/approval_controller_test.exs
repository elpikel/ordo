defmodule OrdoWeb.ApprovalControllerTest do
  use OrdoWeb.ConnCase, async: true

  import Ordo.AccountsFixtures

  alias Ordo.Notifications.Token
  alias Ordo.Repo
  alias Ordo.Support.Message
  alias Ordo.Support.Ticket

  defp draft_ticket(attrs \\ %{}) do
    tenant = tenant_fixture()

    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(
        Enum.into(attrs, %{
          tenant_id: tenant.id,
          customer_name: "Anna",
          subject: "Gdzie paczka?",
          status: "draft_ready",
          draft: "Paczka jest w drodze."
        })
      )
      |> Repo.insert()

    Repo.insert!(Message.changeset(%Message{}, %{ticket_id: ticket.id, role: "customer", body: "Gdzie moja paczka?"}))
    ticket
  end

  describe "show" do
    test "renders the confirmation page with both messages", %{conn: conn} do
      ticket = draft_ticket()
      conn = get(conn, ~p"/n/#{Token.sign(ticket.id)}")

      assert html = html_response(conn, 200)
      assert html =~ "Gdzie moja paczka?"
      assert html =~ "Paczka jest w drodze."
      assert html =~ "method=\"post\""
    end

    test "an invalid token is 404, not a crash", %{conn: conn} do
      conn = get(conn, ~p"/n/not-a-real-token")
      assert html_response(conn, 404)
    end

    test "an already-answered ticket shows the done page", %{conn: conn} do
      ticket = draft_ticket(%{status: "answered"})
      conn = get(conn, ~p"/n/#{Token.sign(ticket.id)}")
      assert html_response(conn, 200) =~ "✓"
    end
  end

  describe "approve" do
    test "sends the draft and marks the ticket answered", %{conn: conn} do
      ticket = draft_ticket()
      conn = post(conn, ~p"/n/#{Token.sign(ticket.id)}")

      assert html_response(conn, 200)
      assert Repo.get!(Ticket, ticket.id).status == "answered"
      assert Repo.get_by(Message, ticket_id: ticket.id, role: "ordo")
    end

    test "a tampered token can't approve anything", %{conn: conn} do
      ticket = draft_ticket()
      tampered = Token.sign(ticket.id) <> "x"
      conn = post(conn, ~p"/n/#{tampered}")

      assert html_response(conn, 404)
      assert Repo.get!(Ticket, ticket.id).status == "draft_ready"
    end
  end
end
