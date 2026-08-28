defmodule OrdoWeb.CacheBodyReader do
  @moduledoc """
  Caches the raw request body on the conn so webhook signatures (e.g. Meta's
  `X-Hub-Signature-256`) can be verified against the exact bytes, which the
  parsed params can't reconstruct. Wired into the endpoint's `Plug.Parsers`.
  """
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
    {:ok, body, conn}
  end

  @doc "The cached raw body as a single binary (empty string if unread)."
  def raw_body(conn) do
    conn.assigns |> Map.get(:raw_body, []) |> Enum.reverse() |> IO.iodata_to_binary()
  end
end
