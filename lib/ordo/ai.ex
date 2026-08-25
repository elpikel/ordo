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
    You are Ordo, a support agent for a Polish e-commerce store selling healthy
    food (muesli, granola, oatmeal). Write a concise, warm reply in language
    "#{language}". Use ONLY the order data and shop rules provided — never invent
    facts, dates, or tracking numbers. If a tracking number is present, include it.
    Sign off with the provided signature. Plain text, no subject line.
    """
  end

  defp compose_user(%{message: message, order: order} = ctx) do
    order_json = if order, do: Jason.encode!(order, pretty: true), else: "brak danych o zamówieniu"
    policy = Map.get(ctx, :policy, [])
    policy_block = if policy == [], do: "brak", else: Enum.map_join(policy, "\n", &("- " <> &1))

    """
    Wiadomość klienta:
    #{message}

    Dane zamówienia z BaseLinkera:
    #{order_json}

    Zasady sklepu (Policy):
    #{policy_block}

    Podpis: #{signature(ctx)}
    """
  end

  defp compose_fallback(%{order: nil} = ctx, _category) do
    "Dzień dobry,\n\nDziękujemy za wiadomość. Aby pomóc, poproszę o numer zamówienia — " <>
      "wtedy sprawdzę szczegóły. W razie potrzeby przekażę sprawę do zespołu.\n\n" <>
      "Pozdrawiamy,\n#{signature(ctx)}"
  end

  defp compose_fallback(%{order: order} = ctx, "PACKAGE_STATUS") do
    name = first_name(order["customer_name"])
    last = List.last(order["courier_history"] || [])
    last_line = if last, do: " Ostatni status: #{last["status"]}.", else: ""

    track =
      if order["tracking"],
        do: " Numer do śledzenia: #{order["tracking"]} (#{order["courier"]}).",
        else: " Paczka jest jeszcze pakowana."

    "Dzień dobry#{name},\n\nZamówienie #{order["number"]} z dnia #{order["date"]} ma status " <>
      "„#{order["status"]}\".#{last_line}#{track}\n\nPozdrawiamy,\n#{signature(ctx)}"
  end

  defp compose_fallback(%{order: order} = ctx, _category) do
    name = first_name(order["customer_name"])
    rules = ctx |> Map.get(:policy, []) |> Enum.take(2) |> Enum.join(" ")
    rules_line = if rules == "", do: "", else: " " <> rules <> "."

    "Dzień dobry#{name},\n\nDotyczy zamówienia #{order["number"]}.#{rules_line} " <>
      "W razie dodatkowych pytań jesteśmy do dyspozycji.\n\nPozdrawiamy,\n#{signature(ctx)}"
  end

  defp signature(ctx), do: Map.get(ctx, :signature) || "Zespół sklepu"

  defp first_name(nil), do: ""
  defp first_name(full), do: " " <> (full |> String.split() |> List.first())

  defp chat(messages, opts \\ []) do
    body = maybe_json_mode(%{model: model(), messages: messages, temperature: 0.3}, opts[:json])

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
