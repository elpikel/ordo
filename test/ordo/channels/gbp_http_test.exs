defmodule Ordo.Channels.Gbp.HTTPTest do
  use Ordo.DataCase, async: false

  import Ordo.AccountsFixtures

  alias Ordo.Channels
  alias Ordo.Channels.Gbp
  alias Ordo.Support.Ticket

  # Route outbound Req calls to a per-process Req.Test stub, and give the adapter
  # OAuth app credentials so it gets past the not-configured guard.
  setup do
    Application.put_env(:ordo, :gbp_req_options, plug: {Req.Test, __MODULE__}, retry: false)
    Application.put_env(:ordo, Gbp.HTTP, client_id: "app-id", client_secret: "app-secret")

    on_exit(fn ->
      Application.delete_env(:ordo, :gbp_req_options)
      Application.delete_env(:ordo, Gbp.HTTP)
    end)

    tenant = tenant_fixture()

    {:ok, channel} =
      Channels.create(%{
        tenant_id: tenant.id,
        type: "gbp",
        name: "Google",
        password: "refresh-token",
        config: %{"account" => "123", "location" => "456"}
      })

    %{tenant: tenant, channel: channel}
  end

  describe "fetch/1" do
    test "mints a token, lists reviews, and normalizes them to the seed shape", %{tenant: tenant} do
      Req.Test.stub(__MODULE__, fn conn ->
        cond do
          conn.request_path == "/token" ->
            Req.Test.json(conn, %{"access_token" => "access-token", "expires_in" => 3600})

          String.ends_with?(conn.request_path, "/456/reviews") ->
            Req.Test.json(conn, %{
              "reviews" => [
                %{
                  "reviewId" => "rev-1",
                  "reviewer" => %{"displayName" => "Anna Kowalska"},
                  "starRating" => "FIVE",
                  "comment" => "Świetna obsługa!",
                  "createTime" => "2024-01-15T10:00:00Z"
                }
              ]
            })

          true ->
            Req.Test.json(conn, %{})
        end
      end)

      assert [review] = Gbp.HTTP.fetch(tenant)
      assert review.id == "rev-1"
      assert review.author == "Anna Kowalska"
      assert review.rating == 5
      assert review.posted == "2024-01-15"
      assert review.text == "Świetna obsługa!"
    end

    test "anonymous reviewer and unspecified rating get safe defaults", %{tenant: tenant} do
      Req.Test.stub(__MODULE__, fn conn ->
        if conn.request_path == "/token" do
          Req.Test.json(conn, %{"access_token" => "access-token"})
        else
          Req.Test.json(conn, %{
            "reviews" => [%{"reviewId" => "rev-2", "reviewer" => %{"isAnonymous" => true}, "starRating" => "UNKNOWN"}]
          })
        end
      end)

      assert [review] = Gbp.HTTP.fetch(tenant)
      assert review.author == "Anonim"
      assert review.rating == 3
      assert review.text == ""
    end

    test "returns [] when the tenant has no gbp channel" do
      other = tenant_fixture()
      assert Gbp.HTTP.fetch(other) == []
    end

    test "returns [] on an API error rather than raising", %{tenant: tenant} do
      Req.Test.stub(__MODULE__, fn conn ->
        if conn.request_path == "/token" do
          Req.Test.json(conn, %{"access_token" => "access-token"})
        else
          conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
        end
      end)

      assert Gbp.HTTP.fetch(tenant) == []
    end
  end

  describe "send_reply/3" do
    test "PUTs the reply to the ticket's own channel and returns :ok", %{tenant: tenant, channel: channel} do
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        if conn.request_path == "/token" do
          Req.Test.json(conn, %{"access_token" => "access-token"})
        else
          send(test_pid, {:replied, conn.method, conn.request_path})
          Req.Test.json(conn, %{"comment" => "ok"})
        end
      end)

      ticket = %Ticket{channel_id: channel.id, meta: %{"review_id" => "rev-1"}}
      assert Gbp.HTTP.send_reply(tenant, ticket, "Dziękujemy!") == :ok
      assert_received {:replied, "PUT", "/v4/accounts/123/locations/456/reviews/rev-1/reply"}
    end

    test "returns {:error, :not_configured} when the ticket has no review id", %{tenant: tenant, channel: channel} do
      assert Gbp.HTTP.send_reply(tenant, %Ticket{channel_id: channel.id, meta: %{}}, "body") ==
               {:error, :not_configured}
    end
  end
end
