defmodule Ordo.Channels.Gbp.OAuth do
  @moduledoc """
  Google OAuth2 (authorization-code) for connecting a Business Profile, plus the
  one-time profile discovery that follows consent.

  `authorize_url/2` builds the consent redirect (`access_type=offline` +
  `prompt=consent` so Google always returns a refresh token). `exchange_code/2`
  trades the callback code for tokens. `discover_profile/1` reads the first
  account + location so the reviews adapter knows what to poll. All calls share
  the adapter's `:gbp_req_options` injection, so tests stub them with `Req.Test`.

  The OAuth app id/secret come from the same config as the reviews adapter
  (`Ordo.Channels.Gbp.HTTP` → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`).
  """

  require Logger

  @auth_endpoint "https://accounts.google.com/o/oauth2/v2/auth"
  @token_endpoint "https://oauth2.googleapis.com/token"
  @accounts_endpoint "https://mybusinessaccountmanagement.googleapis.com/v1/accounts"
  @business_info "https://mybusinessbusinessinformation.googleapis.com/v1"
  @scope "https://www.googleapis.com/auth/business.manage"

  @doc "True once the OAuth app credentials are configured."
  def configured? do
    {id, secret} = client_config()
    is_binary(id) and is_binary(secret)
  end

  @doc "Google consent URL to redirect the operator to."
  def authorize_url(redirect_uri, state) do
    {client_id, _secret} = client_config()

    query =
      URI.encode_query(
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: @scope,
        access_type: "offline",
        prompt: "consent",
        state: state
      )

    @auth_endpoint <> "?" <> query
  end

  @doc "Exchange an authorization code for `%{refresh_token, access_token}`."
  def exchange_code(code, redirect_uri) do
    {client_id, client_secret} = client_config()

    form = [
      code: code,
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    ]

    case request(url: @token_endpoint, method: :post, form: form) do
      {:ok, %{"refresh_token" => refresh} = body} when is_binary(refresh) ->
        {:ok, %{refresh_token: refresh, access_token: body["access_token"]}}

      {:ok, body} ->
        {:error, {:oauth, body["error"] || :no_refresh_token}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Discover the first account + location to read, as `%{account, location}` resource names."
  def discover_profile(access_token) do
    with {:ok, account} <- first_account(access_token),
         {:ok, location} <- first_location(access_token, account) do
      {:ok, %{account: account, location: location}}
    end
  end

  defp first_account(token) do
    case get(token, @accounts_endpoint, %{}) do
      {:ok, %{"accounts" => [%{"name" => name} | _]}} when is_binary(name) -> {:ok, name}
      {:ok, _} -> {:error, :no_account}
      {:error, reason} -> {:error, reason}
    end
  end

  defp first_location(token, account) do
    case get(token, "#{@business_info}/#{account}/locations", %{readMask: "name", pageSize: 1}) do
      {:ok, %{"locations" => [%{"name" => name} | _]}} when is_binary(name) -> {:ok, name}
      {:ok, _} -> {:error, :no_location}
      {:error, reason} -> {:error, reason}
    end
  end

  defp client_config do
    cfg = Application.get_env(:ordo, Ordo.Channels.Gbp.HTTP, [])
    {cfg[:client_id], cfg[:client_secret]}
  end

  defp get(token, url, params) do
    request(url: url, method: :get, params: params, headers: [{"authorization", "Bearer #{token}"}])
  end

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
end
