defmodule Ordo.Accounts.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  alias Ordo.Accounts.User
  alias Ordo.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Ordo", "hello@hireordo.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver an invitation to join Ordo. The link is a magic login URL: clicking it
  logs the user in, confirms their account, and drops them into their tenant's
  inbox, where they can set a password in settings.
  """
  def deliver_invitation(user, url) do
    deliver(user.email, "You've been invited to Ordo", """

    ==============================

    Hi #{user.email},

    You've been invited to Ordo. Click the link below to activate your account
    and log in:

    #{url}

    Once you're in, set a password on the settings page so you can log in again
    later. If you didn't expect this invitation, please ignore this email.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
