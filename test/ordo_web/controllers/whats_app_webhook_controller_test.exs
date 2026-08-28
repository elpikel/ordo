defmodule OrdoWeb.WhatsAppWebhookControllerTest do
  use OrdoWeb.ConnCase, async: false

  import Ordo.AccountsFixtures

  alias Ordo.Repo
  alias Ordo.Support.Message
  alias Ordo.Support.Ticket

  setup do
    Application.put_env(:ordo, :whatsapp_webhook, verify_token: "verify-me", app_secret: nil)
    on_exit(fn -> Application.delete_env(:ordo, :whatsapp_webhook) end)
    :ok
  end

  defp draft_ticket(tenant) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(%{
        tenant_id: tenant.id,
        customer_name: "Anna",
        subject: "Gdzie paczka?",
        status: "draft_ready",
        draft: "Paczka jest w drodze."
      })
      |> Repo.insert()

    Repo.insert!(Message.changeset(%Message{}, %{ticket_id: ticket.id, role: "customer", body: "Gdzie paczka?"}))
    ticket
  end

  defp inbound(from, text) do
    %{
      "entry" => [
        %{
          "changes" => [%{"value" => %{"messages" => [%{"from" => from, "type" => "text", "text" => %{"body" => text}}]}}]
        }
      ]
    }
  end

  describe "verify (Meta handshake)" do
    test "echoes the challenge when the verify token matches", %{conn: conn} do
      conn =
        get(conn, ~p"/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=verify-me&hub.challenge=abc123")

      assert response(conn, 200) == "abc123"
    end

    test "rejects a wrong verify token", %{conn: conn} do
      conn = get(conn, ~p"/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=abc")
      assert response(conn, 403)
    end
  end

  describe "receive" do
    test "an OK reply approves the sender's most recent pending draft", %{conn: conn} do
      tenant = tenant_fixture(%{notify_whatsapp: "+48 600 100 200"})
      ticket = draft_ticket(tenant)

      conn = post(conn, ~p"/webhooks/whatsapp", inbound("48600100200", "OK"))

      assert response(conn, 200)
      assert Repo.get!(Ticket, ticket.id).status == "answered"
    end

    test "a non-approval message is ignored", %{conn: conn} do
      tenant = tenant_fixture(%{notify_whatsapp: "48600100200"})
      ticket = draft_ticket(tenant)

      conn = post(conn, ~p"/webhooks/whatsapp", inbound("48600100200", "kiedy dostawa?"))

      assert response(conn, 200)
      assert Repo.get!(Ticket, ticket.id).status == "draft_ready"
    end

    test "a bad HMAC signature is rejected when an app secret is configured", %{conn: conn} do
      Application.put_env(:ordo, :whatsapp_webhook, verify_token: "verify-me", app_secret: "s3cret")
      tenant = tenant_fixture(%{notify_whatsapp: "48600100200"})
      ticket = draft_ticket(tenant)

      conn =
        conn
        |> put_req_header("x-hub-signature-256", "sha256=deadbeef")
        |> post(~p"/webhooks/whatsapp", inbound("48600100200", "OK"))

      assert response(conn, 401)
      assert Repo.get!(Ticket, ticket.id).status == "draft_ready"
    end
  end
end
