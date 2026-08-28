defmodule Ordo.Channels.GbpPollingTest do
  use Ordo.DataCase, async: false

  import Ordo.AccountsFixtures

  alias Ordo.Channels
  alias Ordo.Channels.Gbp.HTTP
  alias Ordo.Channels.PollReviews
  alias Ordo.Repo
  alias Ordo.Support.Ticket

  setup do
    # receive_review kicks off an async draft pipeline that touches the Repo.
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Application.put_env(:ordo, :gbp_req_options, plug: {Req.Test, __MODULE__}, retry: false)
    Application.put_env(:ordo, HTTP, client_id: "app-id", client_secret: "app-secret")

    on_exit(fn ->
      Application.delete_env(:ordo, :gbp_req_options)
      Application.delete_env(:ordo, HTTP)
    end)

    :ok
  end

  defp gbp_channel(tenant, attrs) do
    {:ok, channel} =
      Channels.create(
        Enum.into(attrs, %{
          tenant_id: tenant.id,
          type: "gbp",
          name: "Google",
          config: %{"account" => "1", "location" => "2"}
        })
      )

    channel
  end

  describe "list_active_reviews/0" do
    test "only active, connected, non-demo gbp channels" do
      connected = tenant_fixture()
      gbp_channel(connected, password: "refresh")

      # excluded: demo tenant
      demo = tenant_fixture(%{demo: true})
      gbp_channel(demo, password: "refresh")

      # excluded: no refresh token (never completed consent)
      gbp_channel(tenant_fixture(), %{})

      # excluded: disabled
      gbp_channel(tenant_fixture(), password: "refresh", active: false)

      tenant_ids = Enum.map(Channels.list_active_reviews(), & &1.tenant_id)
      assert tenant_ids == [connected.id]
    end
  end

  describe "PollReviews.perform/1" do
    test "fetches a profile's reviews, ingests them, and stamps the cursor" do
      tenant = tenant_fixture()
      channel = gbp_channel(tenant, password: "refresh", config: %{"account" => "123", "location" => "456"})

      Req.Test.stub(__MODULE__, fn conn ->
        if conn.request_path == "/token" do
          Req.Test.json(conn, %{"access_token" => "access-token"})
        else
          Req.Test.json(conn, %{
            "reviews" => [
              %{
                "reviewId" => "poll-1",
                "reviewer" => %{"displayName" => "Ola"},
                "starRating" => "FIVE",
                "comment" => "Super!",
                "createTime" => "2024-02-01T09:00:00Z"
              }
            ]
          })
        end
      end)

      assert :ok = PollReviews.perform(%Oban.Job{args: %{"channel_id" => channel.id}})

      ticket = Repo.one!(from t in Ticket, where: t.tenant_id == ^tenant.id)
      assert ticket.channel_id == channel.id
      assert ticket.customer_name == "Ola"
      assert ticket.meta["review_id"] == "poll-1"

      assert Repo.reload!(channel).last_polled_at
    end

    test "is idempotent — a second poll ingests nothing new" do
      tenant = tenant_fixture()
      channel = gbp_channel(tenant, password: "refresh", config: %{"account" => "123", "location" => "456"})

      Req.Test.stub(__MODULE__, fn conn ->
        if conn.request_path == "/token" do
          Req.Test.json(conn, %{"access_token" => "access-token"})
        else
          Req.Test.json(conn, %{
            "reviews" => [
              %{"reviewId" => "dup-1", "reviewer" => %{"displayName" => "X"}, "starRating" => "FOUR", "comment" => "ok"}
            ]
          })
        end
      end)

      job = %Oban.Job{args: %{"channel_id" => channel.id}}
      assert :ok = PollReviews.perform(job)
      assert :ok = PollReviews.perform(job)

      assert Repo.aggregate(from(t in Ticket, where: t.tenant_id == ^tenant.id), :count) == 1
    end

    test "a revoked token flags the profile for reconnect and pauses polling" do
      tenant = tenant_fixture()
      channel = gbp_channel(tenant, password: "revoked", config: %{"account" => "123", "location" => "456"})

      # Google returns 400 invalid_grant when the refresh token is dead.
      Req.Test.stub(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      # Not retryable — the job succeeds so Oban doesn't hammer a dead token.
      assert :ok = PollReviews.perform(%Oban.Job{args: %{"channel_id" => channel.id}})

      assert Repo.aggregate(from(t in Ticket, where: t.tenant_id == ^tenant.id), :count) == 0
      assert Repo.reload!(channel).last_error == Channels.gbp_auth_error()

      # ...and it drops out of the poll set until the operator reconnects.
      refute channel.id in Enum.map(Channels.list_active_reviews(), & &1.id)
    end
  end
end
