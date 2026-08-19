defmodule OrdoWeb.PageController do
  use OrdoWeb, :controller

  def home(conn, _params) do
    # The landing page is a self-contained document (Tailwind CDN + custom
    # fonts/styles), so render it without the root layout that injects
    # app.css, the LiveView JS, and the daisyUI theme.
    conn
    |> put_root_layout(html: false)
    |> render(:home)
  end
end
