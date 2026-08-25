defmodule OrdoWeb.LocaleController do
  @moduledoc "Persists the user's language choice in the session, then returns them where they were."
  use OrdoWeb, :controller

  def update(conn, %{"locale" => locale} = params) do
    conn =
      if locale in OrdoWeb.Locale.supported() do
        put_session(conn, :locale, locale)
      else
        conn
      end

    redirect(conn, to: return_to(conn, params))
  end

  # Prefer an explicit return_to, then the referring page, then the landing page.
  defp return_to(conn, params) do
    with nil <- safe_local(params["return_to"]),
         nil <- conn |> get_req_header("referer") |> List.first() |> referer_path() do
      ~p"/"
    end
  end

  defp referer_path(nil), do: nil
  defp referer_path(referer), do: safe_local(URI.parse(referer).path)

  # Only allow same-site relative paths (avoid open redirects).
  defp safe_local("/" <> _ = path), do: path
  defp safe_local(_), do: nil
end
