defmodule Ordo.Leads.Notifier do
  @moduledoc """
  Sends internal notifications about new leads coming from the landing page.
  """
  import Swoosh.Email

  alias Ordo.Leads.PilotRequest
  alias Ordo.Mailer

  # Who gets pinged when a prospect requests a pilot slot.
  @notify_email "hello@hireordo.com"

  @doc """
  Notify the team that a new prospect requested a pilot slot.
  """
  def deliver_new_pilot_request(%PilotRequest{} = request) do
    email =
      new()
      |> to(@notify_email)
      |> from({"Ordo", "hello@hireordo.com"})
      |> reply_to(request.email)
      |> subject("New pilot request — #{request.email}")
      |> text_body("""
      A new prospect requested a pilot slot from the landing page.

      Email:    #{request.email}
      Locale:   #{request.locale}
      Received: #{request.inserted_at}
      """)

    Mailer.deliver(email)
  end
end
