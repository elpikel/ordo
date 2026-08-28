defmodule Ordo.Channels.Gbp do
  @moduledoc """
  Google Business Profile reviews channel. A tenant can connect several profiles
  (one `gbp` channel per Google account, like mailboxes). Demo tenants use the
  `Fake` adapter (seeded reviews from `Ordo.Demo`); real tenants use `HTTP`
  (OAuth + the My Business reviews API). Adapter is picked by the tenant's `demo`
  flag, like BaseLinker.
  """
  @behaviour Ordo.Channels.Channel

  alias Ordo.Support.Channel
  alias Ordo.Support.Tenant

  @impl true
  def fetch(tenant), do: adapter(tenant).fetch(tenant)

  @impl true
  def send_reply(tenant, ticket, body), do: adapter(tenant).send_reply(tenant, ticket, body)

  @doc """
  Fetch reviews for one connected profile (the poll unit — `channel` carries its
  own creds). Returns `{:ok, reviews}`, or `{:error, :auth}` when the profile's
  refresh token has been revoked/expired and the tenant must reconnect, or
  `{:error, reason}` for a transient failure.
  """
  def fetch_channel(%Channel{tenant: %Tenant{} = tenant} = channel), do: adapter(tenant).fetch_channel(channel)

  defp adapter(%{demo: true}), do: Ordo.Channels.Gbp.Fake
  defp adapter(_), do: Ordo.Channels.Gbp.HTTP
end

defmodule Ordo.Channels.Gbp.Fake do
  @moduledoc "Seeded GBP reviews for the demo; publishing a reply is a no-op."
  @behaviour Ordo.Channels.Channel

  @impl true
  def fetch(_tenant), do: Ordo.Demo.reviews()

  @impl true
  def send_reply(_tenant, _ticket, _body), do: :ok

  @doc "Per-channel fetch — same seeded reviews (demo profiles are never actually polled)."
  def fetch_channel(_channel), do: {:ok, Ordo.Demo.reviews()}
end

defmodule Ordo.Channels.Gbp.HTTP do
  @moduledoc """
  Real Google Business Profile integration: OAuth2 + the My Business v4
  `accounts.locations.reviews` list / reply endpoints.

  Credentials are per **channel** — a tenant may have several connected profiles.
  The encrypted `password` field holds that profile's OAuth **refresh token**,
  and `config` holds its resource ids (`"account"`, `"location"`). The OAuth app
  id/secret are process-wide config (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`).
  Each call mints a short-lived access token from the refresh token.

  Fetch is per-channel; `send_reply/3` targets the ticket's own channel, so a
  reply always goes back to the profile the review came from. Parsing is
  defensive — a poll or an approval never crashes; a revoked/expired refresh
  token surfaces as `{:error, :auth}` so the poll worker can flag the profile for
  reconnection. Response shapes are best-effort against Google's docs and should
  be verified against a real profile (see ADR-0012).
  """
  @behaviour Ordo.Channels.Channel

  alias Ordo.Channels
  alias Ordo.Support.Channel
  alias Ordo.Support.Tenant

  require Logger

  @api "https://mybusiness.googleapis.com/v4"
  @token_endpoint "https://oauth2.googleapis.com/token"
  @page_size 50
  @page_cap 5

  # Tenant-level fetch aggregates every connected profile; the poll worker uses
  # the per-channel `fetch_channel/1` so each profile gets its own job + cursor.
  @impl true
  def fetch(%Tenant{} = tenant), do: tenant.id |> Channels.gbp_channels() |> Enum.flat_map(&reviews/1)
  def fetch(_), do: []

  @doc "Reviews for one connected profile, tagged so the poll worker can react to auth failures."
  def fetch_channel(%Channel{} = channel) do
    with parent when is_binary(parent) <- parent(channel),
         {:ok, token} <- access_token(channel) do
      {:ok, token |> list_reviews(parent) |> Enum.map(&normalize/1)}
    else
      nil -> {:error, :not_configured}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.warning("Gbp.HTTP.fetch failed: #{Exception.message(e)}")
      {:error, :exception}
  end

  @impl true
  def send_reply(_tenant, ticket, body) do
    with %Channel{} = channel <- ticket_channel(ticket),
         parent when is_binary(parent) <- parent(channel),
         review_id when is_binary(review_id) <- review_id(ticket),
         {:ok, token} <- access_token(channel) do
      put_reply(token, "#{parent}/reviews/#{review_id}", body)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_configured}
    end
  rescue
    e ->
      Logger.warning("Gbp.HTTP.send_reply failed: #{Exception.message(e)}")
      {:error, :exception}
  end

  # The tenant-level aggregate just wants a list; drop the tag.
  defp reviews(%Channel{} = channel) do
    case fetch_channel(channel) do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp ticket_channel(%{channel_id: id}) when not is_nil(id), do: Channels.get!(id)
  defp ticket_channel(_), do: nil

  # The `accounts/{id}/locations/{id}` parent that names the profile's reviews,
  # tolerating ids stored either bare or already prefixed.
  defp parent(%{config: config}) when is_map(config) do
    with account when is_binary(account) <- config["account"],
         location when is_binary(location) <- config["location"] do
      "accounts/#{trim(account, "accounts/")}/locations/#{trim(location, "locations/")}"
    else
      _ -> nil
    end
  end

  defp parent(_), do: nil

  defp trim(value, prefix), do: String.replace_prefix(value, prefix, "")

  defp review_id(%{meta: %{"review_id" => id}}) when is_binary(id) and id != "", do: id
  defp review_id(_), do: nil

  # Newest-first pages, bounded so a huge profile can't stall a poll; re-seen
  # reviews are deduped downstream by their `gbp:<reviewId>` message id.
  defp list_reviews(token, parent) do
    1..@page_cap
    |> Enum.reduce_while({[], nil}, fn _page, {acc, page_token} ->
      params = maybe_page(%{pageSize: @page_size}, page_token)

      case get(token, "#{@api}/#{parent}/reviews", params) do
        {:ok, %{"reviews" => reviews} = body} when is_list(reviews) ->
          case body["nextPageToken"] do
            next when is_binary(next) and next != "" -> {:cont, {acc ++ reviews, next}}
            _ -> {:halt, {acc ++ reviews, nil}}
          end

        _ ->
          {:halt, {acc, nil}}
      end
    end)
    |> elem(0)
  end

  defp maybe_page(params, nil), do: params
  defp maybe_page(params, token), do: Map.put(params, :pageToken, token)

  # Into the same shape `Ordo.Demo.reviews/0` produces, so `receive_review/2`
  # doesn't care whether a review came from the Fake or the live API.
  defp normalize(review) do
    %{
      id: review["reviewId"],
      author: reviewer_name(review["reviewer"]),
      author_kind: nil,
      rating: star_to_int(review["starRating"]),
      posted: format_date(review["createTime"]),
      text: review["comment"] || ""
    }
  end

  defp reviewer_name(%{"displayName" => name}) when is_binary(name) and name != "", do: name
  defp reviewer_name(_), do: "Anonim"

  defp star_to_int("FIVE"), do: 5
  defp star_to_int("FOUR"), do: 4
  defp star_to_int("THREE"), do: 3
  defp star_to_int("TWO"), do: 2
  defp star_to_int("ONE"), do: 1
  # Unspecified rating: stay neutral so it's neither auto-thanked nor auto-flagged.
  defp star_to_int(_), do: 3

  defp put_reply(token, name, body) do
    case put(token, "#{@api}/#{name}/reply", %{comment: body}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Exchange the channel's refresh token for a short-lived access token.
  defp access_token(%{password: refresh_token}) when is_binary(refresh_token) and refresh_token != "" do
    case client_config() do
      {id, secret} when is_binary(id) and is_binary(secret) ->
        form = [client_id: id, client_secret: secret, refresh_token: refresh_token, grant_type: "refresh_token"]

        case request(url: @token_endpoint, method: :post, form: form) do
          {:ok, %{"access_token" => token}} when is_binary(token) -> {:ok, token}
          # A revoked/expired refresh token comes back 400/401 (invalid_grant) —
          # a human must reconnect, so tag it distinctly from a transient blip.
          {:error, {:http, status}} when status in [400, 401] -> {:error, :auth}
          {:ok, _body} -> {:error, :auth}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :not_configured}
    end
  end

  defp access_token(_), do: {:error, :not_configured}

  defp client_config do
    cfg = Application.get_env(:ordo, __MODULE__, [])
    {cfg[:client_id], cfg[:client_secret]}
  end

  defp get(token, url, params), do: request(url: url, method: :get, params: params, headers: auth(token))
  defp put(token, url, json), do: request(url: url, method: :put, json: json, headers: auth(token))

  defp auth(token), do: [{"authorization", "Bearer #{token}"}]

  defp request(opts) do
    extra = Application.get_env(:ordo, :gbp_req_options, [])

    case Req.request([receive_timeout: 15_000] ++ opts ++ extra) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> decode(body)
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(body) when is_map(body), do: {:ok, body}

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> {:ok, map}
      _ -> {:error, :decode}
    end
  end

  defp decode(_), do: {:error, :decode}

  defp format_date(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt |> DateTime.to_date() |> Date.to_string()
      _ -> ts
    end
  end

  defp format_date(_), do: nil
end
