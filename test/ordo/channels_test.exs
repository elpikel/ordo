defmodule Ordo.ChannelsTest do
  use Ordo.DataCase, async: false

  import Ordo.AccountsFixtures

  alias Ordo.Channels
  alias Ordo.Channels.Email
  alias Ordo.Channels.Gbp.Fake
  alias Ordo.Demo
  alias Ordo.Repo
  alias Ordo.Support
  alias Ordo.Support.Message
  alias Ordo.Support.Ticket

  setup do
    # Reviews kick off an async draft pipeline that touches the Repo; share the
    # sandbox connection so that task doesn't hit an ownership error.
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  describe "channel routing" do
    test "module/1 maps channel_type to its module" do
      assert Channels.module("gbp") == Ordo.Channels.Gbp
      assert Channels.module("email") == Email
      assert Channels.module("anything-else") == Email
    end
  end

  describe "list_for_tenant/1" do
    test "returns the tenant's channel rows ordered by id" do
      tenant = tenant_fixture()
      {:ok, email} = Channels.create(%{tenant_id: tenant.id, type: "email", email: "sklep@example.com"})
      {:ok, gbp} = Channels.create(%{tenant_id: tenant.id, type: "gbp", name: "Google"})

      ids = tenant.id |> Channels.list_for_tenant() |> Enum.map(& &1.id)
      assert ids == [email.id, gbp.id]
    end
  end

  describe "gbp_channel/1" do
    test "finds the tenant's gbp channel, or nil when there's no integration" do
      tenant = tenant_fixture()
      assert Channels.gbp_channel(tenant.id) == nil

      {:ok, gbp} = Channels.create(%{tenant_id: tenant.id, type: "gbp", name: "Google"})
      assert Channels.gbp_channel(tenant.id).id == gbp.id
    end
  end

  describe "upsert_gbp_channel/3" do
    test "adds a channel per Google account but reconnects (updates) the same account" do
      tenant = tenant_fixture()
      attrs = %{name: "Google", password: "r1", config: %{"account" => "accounts/1", "location" => "locations/9"}}

      {:ok, first} = Channels.upsert_gbp_channel(tenant.id, "accounts/1", attrs)
      # a different account is a second profile...
      {:ok, _second} =
        Channels.upsert_gbp_channel(tenant.id, "accounts/2", %{attrs | config: %{"account" => "accounts/2"}})

      assert length(Channels.gbp_channels(tenant.id)) == 2

      # ...reconnecting the same account refreshes it in place (new token), no dup
      {:ok, again} =
        Channels.upsert_gbp_channel(tenant.id, "accounts/1", %{attrs | password: "r1-new"})

      assert again.id == first.id
      assert again.password == "r1-new"
      assert length(Channels.gbp_channels(tenant.id)) == 2
    end

    test "a reconnect clears a prior auth failure" do
      tenant = tenant_fixture()
      attrs = %{name: "Google", password: "r1", config: %{"account" => "accounts/1"}}
      {:ok, channel} = Channels.upsert_gbp_channel(tenant.id, "accounts/1", attrs)
      Channels.update_cursor(channel, %{last_error: Channels.gbp_auth_error()})

      {:ok, reconnected} = Channels.upsert_gbp_channel(tenant.id, "accounts/1", %{attrs | password: "r2"})
      assert reconnected.last_error == nil
    end
  end

  describe "seed_demo_inbox!/1" do
    test "seeds email + gbp tickets with a customer message each, idempotently" do
      tenant = Support.ensure_demo_tenant!()

      assert :ok = Support.seed_demo_inbox!(tenant)

      gbp = Channels.gbp_channel(tenant.id)
      tickets = Repo.all(from t in Ticket, where: t.tenant_id == ^tenant.id)
      expected = length(Demo.emails()) + length(Demo.reviews())

      assert length(tickets) == expected
      assert Enum.all?(tickets, &(&1.status == "draft_ready"))
      assert Enum.all?(tickets, &(&1.channel_id != nil))
      assert Enum.count(tickets, &(&1.channel_id == gbp.id)) == length(Demo.reviews())
      # one customer message per ticket
      assert Repo.aggregate(from(m in Message, where: m.role == "customer"), :count) == expected

      # idempotent — a second call adds nothing
      assert :ok = Support.seed_demo_inbox!(tenant)
      assert Repo.aggregate(from(t in Ticket, where: t.tenant_id == ^tenant.id), :count) == expected
    end
  end

  describe "fix_demo_account!/1" do
    test "re-homes orphaned review tickets and seeds missing reviews onto the gbp channel" do
      tenant = Support.ensure_demo_tenant!()
      gbp = Channels.gbp_channel(tenant.id)
      [review | _] = Demo.reviews()

      # an orphaned review ticket, as seeded before the gbp channel existed
      {:ok, orphan} =
        %Ticket{}
        |> Ticket.changeset(%{
          tenant_id: tenant.id,
          channel_id: nil,
          customer_name: review.author,
          subject: "old review",
          status: "draft_ready",
          meta: %{"review_id" => review.id}
        })
        |> Repo.insert()

      Repo.insert!(
        Message.changeset(%Message{}, %{
          ticket_id: orphan.id,
          role: "customer",
          body: review.text,
          message_id: "gbp:" <> review.id
        })
      )

      assert :ok = Support.fix_demo_account!(tenant)

      # the orphan now belongs to the gbp channel...
      assert Repo.get!(Ticket, orphan.id).channel_id == gbp.id
      # ...and the remaining reviews were seeded (deduped by message_id)
      reviews = Repo.all(from t in Ticket, where: t.tenant_id == ^tenant.id and t.channel_id == ^gbp.id)
      assert length(reviews) == length(Demo.reviews())
    end
  end

  describe "GBP Fake adapter" do
    test "fetch/1 returns seeded reviews with ratings" do
      reviews = Fake.fetch(%{demo: true})
      assert length(reviews) > 0
      assert Enum.all?(reviews, &(&1.rating in 0..5 and is_binary(&1.author)))
    end

    test "send_reply/3 is a no-op that succeeds" do
      assert Fake.send_reply(%{}, %{}, "reply") == :ok
    end
  end

  describe "Ticket.changeset customer contact" do
    test "a review (name, no email) is valid" do
      cs =
        Ticket.changeset(%Ticket{}, %{
          tenant_id: 1,
          customer_name: "Anna Kowalska",
          subject: "Great service"
        })

      assert cs.valid?
    end

    test "no email and no name is invalid" do
      cs = Ticket.changeset(%Ticket{}, %{tenant_id: 1, subject: "x"})
      refute cs.valid?
      assert %{customer_email: _} = errors_on(cs)
    end
  end

  describe "receive_review/2" do
    setup do
      tenant = tenant_fixture(%{demo: true})
      {:ok, gbp} = Channels.create(%{tenant_id: tenant.id, type: "gbp", name: "Google"})
      %{tenant: tenant, gbp: gbp}
    end

    test "creates a gbp ticket on the gbp channel with rating meta and the review as a customer message", %{
      tenant: tenant,
      gbp: gbp
    } do
      review = %{
        id: "r-test",
        author: "Jan Nowak",
        author_kind: "3 opinie",
        rating: 5,
        posted: "wczoraj",
        text: "Świetna obsługa i szybka wysyłka, polecam!"
      }

      {:ok, ticket} = Support.receive_review(tenant, review)

      ticket = Support.get_ticket!(ticket.id)
      assert Ticket.channel_type(ticket) == "gbp"
      assert ticket.channel.type == "gbp"
      assert ticket.channel_id == gbp.id
      assert ticket.customer_name == "Jan Nowak"
      assert ticket.meta["rating"] == 5
      assert ticket.meta["review_id"] == "r-test"
      assert [%{role: "customer", body: body}] = ticket.messages
      assert body =~ "Świetna obsługa"
    end

    test "is idempotent — the same review is not ingested twice", %{tenant: tenant} do
      review = %{id: "r-dup", author: "X", author_kind: "1 opinia", rating: 4, posted: "dziś", text: "ok"}
      {:ok, _} = Support.receive_review(tenant, review)
      assert {:skip, :duplicate} = Support.receive_review(tenant, review)
      assert Repo.aggregate(Ticket, :count) == 1
    end
  end
end
