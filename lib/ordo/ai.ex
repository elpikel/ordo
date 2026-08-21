defmodule Ordo.AI do
  @moduledoc """
  Classify an inbound email and compose a Polish reply.

  Uses OpenAI Chat Completions when `OPENAI_API_KEY` is set; otherwise falls
  back to deterministic, offline logic that still reads real seeded order data —
  so the demo works on bad conference wifi with no visible difference on screen.
  """

  require Logger

  @endpoint "https://api.openai.com/v1/chat/completions"
  @categories ~w(PACKAGE_STATUS RETURN RETURN_STATUS INVOICE ORDER_CHANGE CANCELLATION COMPLAINT OTHER)

  # --- Classify -----------------------------------------------------------

  @doc "Return %{category, language, order_ref, sentiment} for an email."
  def classify(subject, body) do
    with true <- available?(),
         {:ok, json} <-
           chat(
             [
               %{role: "system", content: classify_system()},
               %{role: "user", content: "Temat: #{subject}\n\nTreść:\n#{body}"}
             ],
             json: true
           ),
         {:ok, map} <- Jason.decode(json) do
      %{
        category: sanitize_category(map["category"]),
        language: map["language"] || "pl",
        order_ref: presence(map["order_ref"]),
        sentiment: map["sentiment"] || "neutral"
      }
    else
      _ -> classify_fallback(subject, body)
    end
  end

  defp classify_system do
    """
    You classify customer-support emails for a Polish e-commerce store.
    Reply with a JSON object: {"category": one of #{Enum.join(@categories, ", ")},
    "language": ISO code (e.g. "pl", "en"), "order_ref": the order number if the
    email mentions one else null, "sentiment": "neutral" or "angry"}.
    Only output the JSON object.
    """
  end

  defp classify_fallback(subject, body) do
    text = String.downcase("#{subject} #{body}")

    category =
      cond do
        text =~ ~r/zwrot|zwróc|odesł/ -> "RETURN"
        text =~ ~r/faktur/ -> "INVOICE"
        text =~ ~r/anul/ -> "CANCELLATION"
        text =~ ~r/reklamac|uszkodz|zepsu/ -> "COMPLAINT"
        text =~ ~r/paczk|przesył|śledz|gdzie|kiedy|dostaw|kurier/ -> "PACKAGE_STATUS"
        true -> "OTHER"
      end

    %{
      category: category,
      language: "pl",
      order_ref: extract_ref(subject, body),
      sentiment: if(text =~ ~r/skandal|fatal|okropn|żenad/, do: "angry", else: "neutral")
    }
  end

  defp extract_ref(subject, body) do
    case Regex.run(~r/[A-Z]{2,4}-\d{3,}/i, "#{subject} #{body}") do
      [ref] -> String.upcase(ref)
      _ -> nil
    end
  end

  # --- Compose ------------------------------------------------------------

  @doc "Compose a reply in the ticket's language, grounded only in the order."
  def compose(%{category: category, language: language} = ctx) do
    with true <- available?(),
         {:ok, text} <-
           chat([
             %{role: "system", content: compose_system(language)},
             %{role: "user", content: compose_user(ctx)}
           ]) do
      String.trim(text)
    else
      _ -> compose_fallback(ctx, category)
    end
  end

  defp compose_system(language) do
    """
    You are Ordo, a support agent for a Polish e-commerce store. Write a concise,
    warm reply in language "#{language}". Use ONLY the order data provided — never
    invent facts, dates, or tracking numbers. If a tracking number is present,
    include it. Sign off as "Zespół sklepu". Plain text, no subject line.
    """
  end

  defp compose_user(%{message: message, order: order}) do
    order_json = if order, do: Jason.encode!(order, pretty: true), else: "brak danych o zamówieniu"

    """
    Wiadomość klienta:
    #{message}

    Dane zamówienia z BaseLinkera:
    #{order_json}
    """
  end

  defp compose_fallback(%{message: _message, order: nil}, _category) do
    "Dzień dobry,\n\nDziękujemy za wiadomość. Przekazuję sprawę do zespołu — " <>
      "odezwiemy się z odpowiedzią najszybciej jak to możliwe.\n\nPozdrawiamy,\nZespół sklepu"
  end

  defp compose_fallback(%{order: order}, "PACKAGE_STATUS") do
    name = first_name(order["customer_name"])
    last = List.last(order["courier_history"] || [])
    last_line = if last, do: " Ostatni status: #{last["status"]} (#{last["date"]}).", else: ""

    "Dzień dobry#{name},\n\nPaczka z zamówienia #{order["number"]} została nadana " <>
      "#{order["date"]} kurierem #{order["courier"]}.#{last_line} " <>
      "Numer do śledzenia: #{order["tracking"]}.\n\nPozdrawiamy,\nZespół sklepu"
  end

  defp compose_fallback(%{order: order}, _category) do
    name = first_name(order["customer_name"])

    "Dzień dobry#{name},\n\nOtrzymaliśmy Twoją wiadomość dotyczącą zamówienia " <>
      "#{order["number"]}. Zajmujemy się nią i wrócimy z odpowiedzią wkrótce.\n\n" <>
      "Pozdrawiamy,\nZespół sklepu"
  end

  defp first_name(nil), do: ""
  defp first_name(full), do: " " <> (full |> String.split() |> List.first())

  # --- OpenAI plumbing ----------------------------------------------------

  defp chat(messages, opts \\ []) do
    body =
      %{model: model(), messages: messages, temperature: 0.3}
      |> maybe_json_mode(opts[:json])

    case Req.post(@endpoint,
           json: body,
           auth: {:bearer, api_key()},
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("OpenAI #{status}: #{inspect(body)}")
        :error

      {:error, reason} ->
        Logger.warning("OpenAI request failed: #{inspect(reason)}")
        :error
    end
  end

  defp maybe_json_mode(body, true), do: Map.put(body, :response_format, %{type: "json_object"})
  defp maybe_json_mode(body, _), do: body

  def available?, do: is_binary(api_key()) and api_key() != ""

  defp api_key, do: System.get_env("OPENAI_API_KEY")
  defp model, do: System.get_env("OPENAI_MODEL") || "gpt-4o-mini"

  defp sanitize_category(cat) when cat in @categories, do: cat
  defp sanitize_category(_), do: "OTHER"

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v
end
