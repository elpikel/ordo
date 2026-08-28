defmodule Ordo.Notifications.WhatsApp do
  @moduledoc """
  Send a WhatsApp message to a shop operator. Demo tenants use the `Fake`
  adapter (logs, no send); real tenants use the Meta `CloudAPI`. Adapter is
  picked by the tenant's `demo` flag, like the other channels.

  A message is either `{:text, body}` (works inside the 24-hour session window)
  or `{:template, name, lang, params}` (a pre-approved template, required for a
  business-initiated message outside that window).
  """
  @type message :: {:text, String.t()} | {:template, String.t(), String.t(), [String.t()]}

  @callback send_message(to :: String.t(), message :: message()) :: :ok | {:error, term()}

  def send_message(tenant, to, message), do: adapter(tenant).send_message(to, message)

  defp adapter(%{demo: true}), do: Ordo.Notifications.WhatsApp.Fake
  defp adapter(_), do: Ordo.Notifications.WhatsApp.CloudAPI
end

defmodule Ordo.Notifications.WhatsApp.Fake do
  @moduledoc "Demo/test WhatsApp: logs the message and succeeds without sending."
  @behaviour Ordo.Notifications.WhatsApp

  require Logger

  @impl true
  def send_message(to, {:text, body}) do
    Logger.info("[WhatsApp.Fake] → #{to}: #{String.slice(body, 0, 80)}…")
    :ok
  end

  def send_message(to, {:template, name, _lang, params}) do
    Logger.info("[WhatsApp.Fake] → #{to}: template #{name}(#{Enum.join(params, ", ")})")
    :ok
  end
end

defmodule Ordo.Notifications.WhatsApp.CloudAPI do
  @moduledoc """
  Meta WhatsApp Cloud API sender (`graph.facebook.com/.../messages`). App
  credentials are process-wide config (`WHATSAPP_TOKEN` / `WHATSAPP_PHONE_ID`).

  When a template is configured (`WHATSAPP_TEMPLATE` + `WHATSAPP_TEMPLATE_LANG`)
  the notifier sends that pre-approved template — the only kind Meta accepts for a
  business-initiated message outside the 24-hour window. Its body carries the full
  original message and proposed reply (as single-line params, since Meta forbids
  newlines in template values) so the operator can decide from the message alone.
  Otherwise it falls back to a plain text message (fine in-session / for testing).
  Best-effort: any failure returns `{:error, _}` so a notification never crashes.
  """
  @behaviour Ordo.Notifications.WhatsApp

  require Logger

  @graph "https://graph.facebook.com/v21.0"

  @impl true
  def send_message(to, message) do
    case config() do
      {token, phone_id} when is_binary(token) and is_binary(phone_id) ->
        post("#{@graph}/#{phone_id}/messages", token, payload(to, message))

      _ ->
        {:error, :not_configured}
    end
  rescue
    e ->
      Logger.warning("WhatsApp.CloudAPI send failed: #{Exception.message(e)}")
      {:error, :exception}
  end

  @doc "The configured approval template as `{name, language}`, or nil for text mode."
  def template do
    cfg = Application.get_env(:ordo, __MODULE__, [])

    case cfg[:template_name] do
      name when is_binary(name) and name != "" -> {name, cfg[:template_language] || "pl"}
      _ -> nil
    end
  end

  defp payload(to, {:text, body}) do
    %{
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: normalize(to),
      type: "text",
      text: %{preview_url: false, body: body}
    }
  end

  defp payload(to, {:template, name, lang, params}) do
    %{
      messaging_product: "whatsapp",
      to: normalize(to),
      type: "template",
      template: %{
        name: name,
        language: %{code: lang},
        components: [%{type: "body", parameters: Enum.map(params, &%{type: "text", text: to_string(&1)})}]
      }
    }
  end

  # Meta wants the number in international format, digits only (no '+').
  defp normalize(number), do: String.replace(number, ~r/\D/, "")

  defp config do
    cfg = Application.get_env(:ordo, __MODULE__, [])
    {cfg[:token], cfg[:phone_number_id]}
  end

  defp post(url, token, body) do
    extra = Application.get_env(:ordo, :whatsapp_req_options, [])

    request =
      [
        url: url,
        method: :post,
        json: body,
        headers: [{"authorization", "Bearer #{token}"}],
        receive_timeout: 15_000
      ] ++ extra

    case Req.request(request) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
