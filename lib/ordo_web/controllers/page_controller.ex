defmodule OrdoWeb.PageController do
  use OrdoWeb, :controller

  alias Ordo.Leads

  def home(conn, params) do
    # The landing page is a self-contained document (Tailwind CDN + custom
    # fonts/styles), so render it without the root layout that injects
    # app.css, the LiveView JS, and the daisyUI theme.
    conn
    |> put_root_layout(html: false)
    |> assign(:pilot_status, params["pilot"])
    |> render(:home)
  end

  # Handles the landing-page "Request a slot" form. The form submits via `fetch`
  # (see home.html.heex) so the page never reloads — those requests get a JSON
  # reply. A plain form POST (no JS) still works and falls back to a redirect
  # that re-anchors the visitor at the form with the outcome in a query param.
  def pilot(conn, %{"pilot_request" => %{"email" => email}}) do
    attrs = %{email: email, locale: Gettext.get_locale(OrdoWeb.Gettext)}

    case Leads.create_pilot_request(attrs) do
      {:ok, _request} -> respond(conn, :sent)
      {:error, _changeset} -> respond(conn, :error)
    end
  end

  def pilot(conn, _params), do: respond(conn, :error)

  defp respond(conn, status) do
    if ajax?(conn) do
      code = if status == :sent, do: 200, else: 422
      conn |> put_status(code) |> json(%{status: status})
    else
      redirect(conn, to: "/?pilot=#{status}#early-access")
    end
  end

  defp ajax?(conn) do
    conn |> get_req_header("x-requested-with") |> List.first() == "fetch"
  end
end
