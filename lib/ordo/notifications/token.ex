defmodule Ordo.Notifications.Token do
  @moduledoc """
  Signed, expiring one-click approval tokens. A token carries just the ticket id,
  signed with the endpoint's secret — no DB row, tamper-proof, and self-expiring.
  Used in the approval email button and (indirectly) the WhatsApp reply flow.
  """

  @salt "ticket approval v1"
  @max_age 7 * 24 * 60 * 60

  @doc "Sign an approval token for a ticket."
  def sign(ticket_id) when is_integer(ticket_id) do
    Phoenix.Token.sign(OrdoWeb.Endpoint, @salt, ticket_id)
  end

  @doc "Verify a token, returning `{:ok, ticket_id}` or `{:error, :expired | :invalid}`."
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(OrdoWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_), do: {:error, :invalid}
end
