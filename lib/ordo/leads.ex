defmodule Ordo.Leads do
  @moduledoc """
  Prospects captured from the public landing page — currently the pilot-program
  "Request a slot" form. Each submission is persisted and the team is notified
  by email.
  """
  alias Ordo.Leads.Notifier
  alias Ordo.Leads.PilotRequest
  alias Ordo.Repo

  @doc """
  Persist a pilot request and email the team about it.

  Notification failures are logged but don't fail the request — the prospect's
  email is already safely stored.
  """
  def create_pilot_request(attrs) do
    with {:ok, request} <- %PilotRequest{} |> PilotRequest.changeset(attrs) |> Repo.insert() do
      case Notifier.deliver_new_pilot_request(request) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          require Logger

          Logger.error("Failed to notify team of pilot request #{request.id}: #{inspect(reason)}")
      end

      {:ok, request}
    end
  end
end
