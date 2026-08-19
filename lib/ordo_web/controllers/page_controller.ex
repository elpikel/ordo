defmodule OrdoWeb.PageController do
  use OrdoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
