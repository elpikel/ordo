defmodule Ordo.NotificationsTest do
  use Ordo.DataCase, async: false

  import Ordo.AccountsFixtures
  import Swoosh.TestAssertions

  alias Ordo.Accounts
  alias Ordo.Notifications
  alias Ordo.Notifications.WhatsApp.CloudAPI
  alias Ordo.Repo
  alias Ordo.Support.Message
  alias Ordo.Support.Ticket

  setup do
    Application.put_env(:ordo, :whatsapp_req_options, plug: {Req.Test, __MODULE__}, retry: false)
    Application.put_env(:ordo, CloudAPI, token: "wa-token", phone_number_id: "wa-phone")

    on_exit(fn ->
      Application.delete_env(:ordo, :whatsapp_req_options)
      Application.delete_env(:ordo, CloudAPI)
    end)

    :ok
  end

  defp draft_ticket(tenant, attrs \\ %{}) do
    {:ok, ticket} =
      %Ticket{}
      |> Ticket.changeset(
        Enum.into(attrs, %{
          tenant_id: tenant.id,
          customer_name: "Anna Nowak",
          subject: "Gdzie paczka?",
          status: "draft_ready",
          draft: "Dzień dobry, paczka jest w drodze."
        })
      )
      |> Repo.insert()

    Repo.insert!(Message.changeset(%Message{}, %{ticket_id: ticket.id, role: "customer", body: "Gdzie moja paczka?"}))
    ticket
  end

  describe "deliver_new_draft/1" do
    test "emails every teammate and sends WhatsApp when enabled" do
      tenant = tenant_fixture(%{notify_enabled: true, notify_whatsapp: "+48 600 100 200"})
      {:ok, _} = Accounts.create_tenant_user(tenant, "owner@shop.pl")
      {:ok, _} = Accounts.create_tenant_user(tenant, "clerk@shop.pl")
      ticket = draft_ticket(tenant)

      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, raw, _} = Plug.Conn.read_body(conn)
        send(test_pid, {:whatsapp, conn.request_path, Jason.decode!(raw)})
        Req.Test.json(conn, %{"messages" => [%{"id" => "wamid.1"}]})
      end)

      assert :ok = Notifications.deliver_new_draft(ticket.id)

      assert_email_sent(fn email ->
        assert {_, "owner@shop.pl"} = Enum.find(email.to, fn {_, addr} -> addr == "owner@shop.pl" end)
        assert email.html_body =~ "Gdzie moja paczka?"
        assert email.html_body =~ "paczka jest w drodze"
      end)

      assert_email_sent(fn email -> Enum.any?(email.to, fn {_, a} -> a == "clerk@shop.pl" end) end)

      # text mode (no template configured) carries the per-draft reply code
      assert_received {:whatsapp, "/v21.0/wa-phone/messages", payload}
      assert payload["type"] == "text"
      assert payload["text"]["body"] =~ "OK #{ticket.id}"
    end

    test "sends the approved template when one is configured" do
      Application.put_env(:ordo, CloudAPI,
        token: "wa-token",
        phone_number_id: "wa-phone",
        template_name: "new_reply",
        template_language: "pl"
      )

      tenant = tenant_fixture(%{notify_enabled: true, notify_whatsapp: "+48600100200"})
      {:ok, _} = Accounts.create_tenant_user(tenant, "owner@shop.pl")
      ticket = draft_ticket(tenant)
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, raw, _} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(raw)})
        Req.Test.json(conn, %{"messages" => [%{"id" => "wamid.2"}]})
      end)

      assert :ok = Notifications.deliver_new_draft(ticket.id)

      assert_received {:payload, payload}
      assert payload["type"] == "template"
      assert payload["template"]["name"] == "new_reply"
      assert payload["template"]["language"]["code"] == "pl"

      # the template carries the full message + reply so the operator can decide,
      # plus the reply code — and no param contains a newline (Meta forbids it)
      [%{"parameters" => params}] = payload["template"]["components"]
      texts = Enum.map(params, & &1["text"])
      assert "Anna Nowak" in texts
      assert Enum.any?(texts, &(&1 =~ "Gdzie moja paczka?"))
      assert Enum.any?(texts, &(&1 =~ "paczka jest w drodze"))
      assert to_string(ticket.id) in texts
      refute Enum.any?(texts, &String.contains?(&1, "\n"))
    end

    test "does nothing when notifications are off" do
      tenant = tenant_fixture(%{notify_enabled: false, notify_whatsapp: "+48600100200"})
      {:ok, _} = Accounts.create_tenant_user(tenant, "owner@shop.pl")
      ticket = draft_ticket(tenant)

      assert :ok = Notifications.deliver_new_draft(ticket.id)
      assert_no_email_sent()
    end

    test "does nothing for a demo tenant even if enabled" do
      tenant = tenant_fixture(%{demo: true, notify_enabled: true})
      {:ok, _} = Accounts.create_tenant_user(tenant, "demo@shop.pl")
      ticket = draft_ticket(tenant)

      assert :ok = Notifications.deliver_new_draft(ticket.id)
      assert_no_email_sent()
    end

    test "skips WhatsApp when no number is set (email only)" do
      tenant = tenant_fixture(%{notify_enabled: true, notify_whatsapp: nil})
      {:ok, _} = Accounts.create_tenant_user(tenant, "owner@shop.pl")
      ticket = draft_ticket(tenant)

      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{}) end)
      assert :ok = Notifications.deliver_new_draft(ticket.id)

      assert_email_sent()
      refute_received {:whatsapp, _}
    end
  end

  describe "pending_ticket_for/2" do
    test "matches the sender's tenant and its most recent pending draft" do
      tenant = tenant_fixture(%{notify_whatsapp: "+48 600 100 200"})
      _old = draft_ticket(tenant, %{subject: "old"})
      newest = draft_ticket(tenant, %{subject: "new"})

      # sender arrives digits-only, as Meta delivers it
      found = Notifications.pending_ticket_for("48600100200", "OK")
      assert found.id == newest.id
    end

    test "an explicit id in the text targets that ticket" do
      tenant = tenant_fixture(%{notify_whatsapp: "48600100200"})
      target = draft_ticket(tenant)
      _other = draft_ticket(tenant)

      assert Notifications.pending_ticket_for("48600100200", "OK #{target.id}").id == target.id
    end

    test "returns nil for an unknown number" do
      assert Notifications.pending_ticket_for("48999999999", "OK") == nil
    end
  end
end
