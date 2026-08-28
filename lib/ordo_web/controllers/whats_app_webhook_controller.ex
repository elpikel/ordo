defmodule OrdoWeb.WhatsAppWebhookController do
  @moduledoc """
  Meta WhatsApp Cloud API webhook. `verify` answers Meta's subscription
  handshake; `receive` takes inbound messages and, when an operator replies "OK"
  (optionally with a ticket id), sends the matching pending draft. Inbound POSTs
  are authenticated by the `X-Hub-Signature-256` HMAC when an app secret is set.
  """
  use OrdoWeb, :controller

  alias Ordo.Notifications
  alias Ordo.Support
  alias OrdoWeb.CacheBodyReader

  require Logger

  # Meta's subscription verification handshake.
  def verify(conn, %{"hub.mode" => "subscribe", "hub.challenge" => challenge} = params) do
    if params["hub.verify_token"] == config(:verify_token) do
      send_resp(conn, 200, challenge)
    else
      send_resp(conn, 403, "")
    end
  end

  def verify(conn, _params), do: send_resp(conn, 400, "")

  def receive(conn, params) do
    if authentic?(conn) do
      params |> messages() |> Enum.each(&handle_message/1)
      send_resp(conn, 200, "")
    else
      send_resp(conn, 401, "")
    end
  end

  # Only act on "OK"/"TAK" (optionally "OK 4821"); everything else is ignored.
  defp handle_message(%{"from" => from, "text" => %{"body" => text}}) when is_binary(from) do
    if approval?(text) do
      case Notifications.pending_ticket_for(from, text) do
        %{} = ticket -> Support.approve_and_send(ticket, ticket.draft || "")
        _ -> Logger.info("WhatsApp OK from #{from} matched no pending ticket")
      end
    end
  end

  defp handle_message(_), do: :ok

  defp approval?(text), do: is_binary(text) and Regex.match?(~r/^\s*(ok|tak)\b/i, text)

  defp messages(params) do
    for entry <- List.wrap(params["entry"]),
        change <- List.wrap(entry["changes"]),
        msg <- List.wrap(get_in(change, ["value", "messages"])),
        do: msg
  end

  # Verify the payload came from Meta. If no app secret is configured (dev), skip.
  defp authentic?(conn) do
    case config(:app_secret) do
      secret when is_binary(secret) and secret != "" -> valid_signature?(conn, secret)
      _ -> true
    end
  end

  defp valid_signature?(conn, secret) do
    case get_req_header(conn, "x-hub-signature-256") do
      [header | _] ->
        expected =
          "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, CacheBodyReader.raw_body(conn)), case: :lower)

        Plug.Crypto.secure_compare(header, expected)

      _ ->
        false
    end
  end

  defp config(key), do: :ordo |> Application.get_env(:whatsapp_webhook, []) |> Keyword.get(key)
end
