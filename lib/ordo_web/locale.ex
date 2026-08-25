defmodule OrdoWeb.Locale do
  @moduledoc """
  Resolves and applies the active locale for Gettext.

  Priority: explicit choice in the session > best match from the browser's
  `Accept-Language` header > the default locale. Used both as a plug (for
  controllers/dead views) and as a LiveView `on_mount` hook (LiveViews run in a
  separate process and must re-apply the locale from the session).
  """
  import Plug.Conn

  @supported ~w(pl en)
  @default "pl"

  @doc "Locales the app ships translations for."
  def supported, do: @supported

  @doc "Fallback locale when nothing else matches."
  def default, do: @default

  ## Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = resolve(conn)
    Gettext.put_locale(OrdoWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  defp resolve(conn) do
    session_locale(get_session(conn, :locale)) || browser_locale(conn) || @default
  end

  defp session_locale(locale) when locale in @supported, do: locale
  defp session_locale(_), do: nil

  defp browser_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> negotiate()
  end

  @doc """
  Picks the best supported locale from an `Accept-Language` header value, or
  `nil` if none match. Public so it can be unit-tested.
  """
  def negotiate(nil), do: nil

  def negotiate(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_tag/1)
    |> Enum.reject(&is_nil(elem(&1, 0)))
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.find_value(fn {locale, _q} -> if locale in @supported, do: locale end)
  end

  defp parse_tag(tag) do
    case String.split(tag, ";") do
      [lang] -> {primary(lang), 1.0}
      [lang, q] -> {primary(lang), parse_q(q)}
      _ -> {nil, 0.0}
    end
  end

  defp primary(lang) do
    lang |> String.trim() |> String.downcase() |> String.split("-") |> List.first()
  end

  defp parse_q("q=" <> value) do
    case Float.parse(value) do
      {q, _} -> q
      :error -> 0.0
    end
  end

  defp parse_q(_), do: 1.0

  ## LiveView

  def on_mount(:default, _params, session, socket) do
    locale = session_locale(session["locale"]) || @default
    Gettext.put_locale(OrdoWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
