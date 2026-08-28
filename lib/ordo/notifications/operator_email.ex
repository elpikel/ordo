defmodule Ordo.Notifications.OperatorEmail do
  @moduledoc """
  The "new reply to approve" email: shows the customer's original message and
  Ordo's proposed reply, with a one-click Approve & send button (signed link)
  and a link to edit in the inbox.
  """
  use Gettext, backend: OrdoWeb.Gettext

  import Swoosh.Email

  alias Ordo.Mailer

  def deliver_new_draft(recipient, ctx) do
    email =
      new()
      |> to(recipient)
      |> from({"Ordo", "hello@hireordo.com"})
      |> subject(gettext("New reply to approve — %{name}", name: ctx.customer_name))
      |> text_body(text_body(ctx))
      |> html_body(html_body(ctx))

    Mailer.deliver(email)
  end

  defp text_body(ctx) do
    """
    #{gettext("New message from %{name}", name: ctx.customer_name)}

    #{gettext("Original message")}:
    #{ctx.original}

    #{gettext("Ordo's proposed reply")}:
    #{ctx.draft}

    #{gettext("Approve and send")}: #{ctx.approve_url}
    #{gettext("Edit in the inbox")}: #{ctx.inbox_url}
    """
  end

  defp html_body(ctx) do
    """
    <!DOCTYPE html>
    <html lang="#{Gettext.get_locale(OrdoWeb.Gettext)}">
      <body style="margin:0;padding:0;background:#f4f6f8;font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#16233b;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f8;padding:32px 0;">
          <tr>
            <td align="center">
              <table role="presentation" width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;background:#ffffff;border:1px solid #e2e8f0;">
                <tr>
                  <td style="padding:18px 28px;border-bottom:2px solid #16233b;">
                    <span style="font-family:'IBM Plex Mono',monospace;font-weight:600;letter-spacing:0.3em;font-size:16px;color:#16233b;">ORDO<span style="color:#b8860b;">.</span></span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px;">
                    <p style="margin:0 0 4px;font-family:'Space Grotesk','IBM Plex Sans',sans-serif;font-weight:700;font-size:20px;color:#16233b;">#{gettext("New reply to approve")}</p>
                    <p style="margin:0 0 20px;color:#5a6a85;font-size:14px;">#{gettext("From %{name}", name: ctx.customer_name)} · #{ctx.subject}</p>

                    <p style="margin:0 0 6px;font-family:'IBM Plex Mono',monospace;font-size:11px;letter-spacing:0.15em;color:#5a6a85;">#{String.upcase(gettext("Original message"))}</p>
                    <div style="margin:0 0 20px;padding:14px 16px;background:#f4f6f8;border:1px solid #e2e8f0;color:#2b3a57;font-size:14px;line-height:1.5;white-space:pre-wrap;">#{escape(ctx.original)}</div>

                    <p style="margin:0 0 6px;font-family:'IBM Plex Mono',monospace;font-size:11px;letter-spacing:0.15em;color:#b8860b;">#{String.upcase(gettext("Ordo's proposed reply"))}</p>
                    <div style="margin:0 0 24px;padding:14px 16px;background:#fffdf5;border:1px solid #e7d9a8;color:#2b3a57;font-size:14px;line-height:1.5;white-space:pre-wrap;">#{escape(ctx.draft)}</div>

                    <a href="#{ctx.approve_url}" style="display:inline-block;background:#16233b;color:#ffffff;font-family:'IBM Plex Mono',monospace;font-size:14px;text-decoration:none;padding:12px 22px;">#{gettext("Approve and send")} &rarr;</a>
                    <p style="margin:18px 0 0;color:#5a6a85;font-size:13px;line-height:1.5;">#{gettext("Want to tweak it first?")} <a href="#{ctx.inbox_url}" style="color:#b8860b;">#{gettext("Edit in the inbox")}</a></p>
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

  defp escape(nil), do: ""

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
