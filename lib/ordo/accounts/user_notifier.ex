defmodule Ordo.Accounts.UserNotifier do
  @moduledoc false
  use Gettext, backend: OrdoWeb.Gettext

  import Swoosh.Email

  alias Ordo.Accounts.User
  alias Ordo.Mailer

  # Delivers a branded, multipart email. The plaintext part always carries the
  # action URL verbatim (some clients prefer text; our tests also parse it there).
  defp deliver(recipient, subject, text, html) do
    email =
      new()
      |> to(recipient)
      |> from({"Ordo", "hello@hireordo.com"})
      |> subject(subject)
      |> text_body(text)
      |> html_body(html)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      gettext("Update email instructions"),
      text_email(
        user.email,
        gettext("You can change your email by visiting the URL below:"),
        url,
        gettext("If you didn't request this change, please ignore this.")
      ),
      html_email(
        user.email,
        gettext("Confirm your new email"),
        gettext("Confirm the change to your Ordo account email by clicking the button below."),
        url,
        gettext("Confirm email change"),
        gettext("If you didn't request this change, you can safely ignore this email.")
      )
    )
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
    deliver(
      user.email,
      gettext("Log in instructions"),
      text_email(
        user.email,
        gettext("You can log into your account by visiting the URL below:"),
        url,
        gettext("If you didn't request this email, please ignore this.")
      ),
      html_email(
        user.email,
        gettext("Log in to Ordo"),
        gettext("Click the button below to log in to your Ordo account."),
        url,
        gettext("Log in"),
        gettext("If you didn't request this email, you can safely ignore it.")
      )
    )
  end

  @doc """
  Deliver an invitation to join Ordo. The link is a magic login URL: clicking it
  logs the user in, confirms their account, and drops them into their tenant's
  inbox, where they can set a password in settings.
  """
  def deliver_invitation(user, url) do
    deliver(
      user.email,
      gettext("You've been invited to Ordo"),
      text_email(
        user.email,
        gettext("You've been invited to Ordo. Click the link below to activate your account and log in:"),
        url,
        gettext(
          "Once you're in, set a password on the settings page so you can log in again later. If you didn't expect this invitation, please ignore this email."
        )
      ),
      html_email(
        user.email,
        gettext("You've been invited to Ordo"),
        gettext(
          "Ordo handles your shop's support email — reads it, pulls the order from BaseLinker, and drafts the reply. Click below to activate your account and open your inbox."
        ),
        url,
        gettext("Activate account"),
        gettext(
          "Once you're in, set a password on the settings page so you can log in again later. If you didn't expect this invitation, please ignore this email."
        )
      )
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      gettext("Confirmation instructions"),
      text_email(
        user.email,
        gettext("You can confirm your account by visiting the URL below:"),
        url,
        gettext("If you didn't create an account with us, please ignore this.")
      ),
      html_email(
        user.email,
        gettext("Confirm your Ordo account"),
        gettext("Confirm your Ordo account by clicking the button below."),
        url,
        gettext("Confirm account"),
        gettext("If you didn't create an account with us, you can safely ignore this email.")
      )
    )
  end

  defp text_email(email, line, url, disclaimer) do
    """

    ==============================

    #{gettext("Hi %{email},", email: email)}

    #{line}

    #{url}

    #{disclaimer}

    ==============================
    """
  end

  defp html_email(email, heading, body, url, cta, disclaimer) do
    """
    <!DOCTYPE html>
    <html lang="#{Gettext.get_locale(OrdoWeb.Gettext)}">
      <body style="margin:0;padding:0;background:#f4f6f8;font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#16233b;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8;padding:32px 0;">
          <tr>
            <td align="center">
              <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background:#ffffff;border:1px solid #e2e8f0;">
                <tr>
                  <td style="padding:18px 28px;border-bottom:2px solid #16233b;">
                    <span style="font-family:'IBM Plex Mono',monospace;font-weight:600;letter-spacing:0.3em;font-size:16px;color:#16233b;">ORDO<span style="color:#b8860b;">.</span></span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px;">
                    <p style="margin:0 0 16px;font-family:'Space Grotesk','IBM Plex Sans',sans-serif;font-weight:700;font-size:22px;color:#16233b;">#{heading}</p>
                    <p style="margin:0 0 12px;color:#2b3a57;font-size:15px;line-height:1.5;">#{gettext("Hi %{email},", email: email)}</p>
                    <p style="margin:0 0 22px;color:#2b3a57;font-size:15px;line-height:1.5;">#{body}</p>
                    <a href="#{url}" style="display:inline-block;background:#16233b;color:#ffffff;font-family:'IBM Plex Mono',monospace;font-size:14px;text-decoration:none;padding:12px 22px;">#{cta} &rarr;</a>
                    <p style="margin:22px 0 0;color:#5a6a85;font-size:13px;line-height:1.5;">#{gettext("Or paste this link into your browser:")}<br />
                      <a href="#{url}" style="color:#b8860b;word-break:break-all;">#{url}</a>
                    </p>
                    <p style="margin:16px 0 0;color:#5a6a85;font-size:13px;line-height:1.5;">#{disclaimer}</p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:18px 28px;border-top:1px solid #e2e8f0;font-size:12px;color:#5a6a85;">
                    #{gettext("Ordo — AI customer support for e-commerce")} · <a href="https://hireordo.com" style="color:#5a6a85;">hireordo.com</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end
end
