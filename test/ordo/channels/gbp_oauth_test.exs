defmodule Ordo.Channels.Gbp.OAuthTest do
  use ExUnit.Case, async: false

  alias Ordo.Channels.Gbp.HTTP
  alias Ordo.Channels.Gbp.OAuth

  setup do
    Application.put_env(:ordo, :gbp_req_options, plug: {Req.Test, __MODULE__}, retry: false)
    Application.put_env(:ordo, HTTP, client_id: "app-id", client_secret: "app-secret")

    on_exit(fn ->
      Application.delete_env(:ordo, :gbp_req_options)
      Application.delete_env(:ordo, HTTP)
    end)

    :ok
  end

  describe "configured?/0" do
    test "true only when both id and secret are present" do
      assert OAuth.configured?()
      Application.put_env(:ordo, HTTP, client_id: "app-id")
      refute OAuth.configured?()
    end
  end

  describe "authorize_url/2" do
    test "carries the app id, redirect, offline consent, and state" do
      url = OAuth.authorize_url("https://ordo.test/oauth/google/callback", "st-8")
      %URI{query: query} = URI.parse(url)
      params = URI.decode_query(query)

      assert params["client_id"] == "app-id"
      assert params["redirect_uri"] == "https://ordo.test/oauth/google/callback"
      assert params["access_type"] == "offline"
      assert params["prompt"] == "consent"
      assert params["state"] == "st-8"
      assert params["scope"] =~ "business.manage"
    end
  end

  describe "exchange_code/2" do
    test "returns the refresh and access tokens" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"refresh_token" => "refresh-xyz", "access_token" => "access-xyz"})
      end)

      assert {:ok, %{refresh_token: "refresh-xyz", access_token: "access-xyz"}} =
               OAuth.exchange_code("the-code", "https://ordo.test/cb")
    end

    test "errors when Google returns no refresh token" do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"error" => "invalid_grant"}) end)
      assert {:error, {:oauth, "invalid_grant"}} = OAuth.exchange_code("bad", "https://ordo.test/cb")
    end
  end

  describe "discover_profile/1" do
    test "picks the first account and its first location" do
      Req.Test.stub(__MODULE__, fn conn ->
        cond do
          String.ends_with?(conn.request_path, "/v1/accounts") ->
            Req.Test.json(conn, %{"accounts" => [%{"name" => "accounts/123"}, %{"name" => "accounts/999"}]})

          String.ends_with?(conn.request_path, "/locations") ->
            Req.Test.json(conn, %{"locations" => [%{"name" => "locations/456"}]})

          true ->
            Req.Test.json(conn, %{})
        end
      end)

      assert {:ok, %{account: "accounts/123", location: "locations/456"}} = OAuth.discover_profile("access-token")
    end

    test "errors when the profile has no location" do
      Req.Test.stub(__MODULE__, fn conn ->
        if String.ends_with?(conn.request_path, "/v1/accounts") do
          Req.Test.json(conn, %{"accounts" => [%{"name" => "accounts/123"}]})
        else
          Req.Test.json(conn, %{"locations" => []})
        end
      end)

      assert {:error, :no_location} = OAuth.discover_profile("access-token")
    end
  end
end
