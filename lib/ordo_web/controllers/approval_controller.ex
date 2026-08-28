defmodule OrdoWeb.ApprovalController do
  @moduledoc """
  One-click draft approval from the operator notification email. The emailed
  button is a GET that renders a confirmation page (safe from mail-scanner
  prefetch); the actual send is the POST from that page. Authorized entirely by
  the signed token — no login.
  """
  use OrdoWeb, :controller

  alias Ordo.Notifications.Token
  alias Ordo.Support

  def show(conn, %{"token" => token}) do
    case ticket_from(token) do
      {:ok, %{status: "answered"} = ticket} -> render_page(conn, done_page(ticket))
      {:ok, ticket} -> render_page(conn, confirm_page(conn, ticket))
      {:error, _} -> render_page(conn, invalid_page(), 404)
    end
  end

  def approve(conn, %{"token" => token}) do
    case ticket_from(token) do
      {:ok, %{status: "answered"} = ticket} ->
        render_page(conn, done_page(ticket))

      {:ok, ticket} ->
        {:ok, ticket} = Support.approve_and_send(ticket, ticket.draft || "")
        render_page(conn, done_page(ticket))

      {:error, _} ->
        render_page(conn, invalid_page(), 404)
    end
  end

  defp ticket_from(token) do
    with {:ok, id} <- Token.verify(token) do
      {:ok, Support.get_ticket!(id)}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp render_page(conn, body, status \\ 200) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end

  defp confirm_page(conn, ticket) do
    page(gettext("Approve reply"), """
    <p style="margin:0 0 4px;font-weight:700;font-size:20px;">#{gettext("Approve this reply?")}</p>
    <p style="margin:0 0 20px;color:#5a6a85;font-size:14px;">#{esc(ticket.customer_name)} · #{esc(ticket.subject)}</p>
    #{block(gettext("Original message"), original(ticket), "#f4f6f8", "#e2e8f0")}
    #{block(gettext("Ordo's proposed reply"), ticket.draft, "#fffdf5", "#e7d9a8")}
    <form method="post" action="#{Phoenix.Controller.current_path(conn)}" style="margin-top:24px;">
      <button type="submit" style="background:#16233b;color:#fff;font-family:'IBM Plex Mono',monospace;font-size:14px;border:0;padding:12px 22px;cursor:pointer;">#{gettext("Send this reply")} &rarr;</button>
    </form>
    """)
  end

  defp done_page(ticket) do
    page(gettext("Reply sent"), """
    <p style="margin:0 0 8px;font-weight:700;font-size:20px;">#{gettext("Reply sent ✓")}</p>
    <p style="margin:0 0 20px;color:#5a6a85;font-size:14px;">#{gettext("This message has been answered — you can close this tab.")}</p>
    #{block(gettext("Sent reply"), ticket.draft, "#f4f6f8", "#e2e8f0")}
    """)
  end

  defp invalid_page do
    page(gettext("Link expired"), """
    <p style="margin:0 0 8px;font-weight:700;font-size:20px;">#{gettext("This link is no longer valid")}</p>
    <p style="margin:0;color:#5a6a85;font-size:14px;">#{gettext("Open the inbox to review and reply.")}</p>
    """)
  end

  defp original(ticket) do
    case Enum.find(ticket.messages || [], &(&1.role == "customer")) do
      %{body: body} -> body
      _ -> ""
    end
  end

  defp block(label, text, bg, border) do
    """
    <p style="margin:0 0 6px;font-family:'IBM Plex Mono',monospace;font-size:11px;letter-spacing:0.15em;color:#5a6a85;">#{String.upcase(label)}</p>
    <div style="margin:0 0 20px;padding:14px 16px;background:#{bg};border:1px solid #{border};color:#2b3a57;font-size:14px;line-height:1.5;white-space:pre-wrap;">#{esc(text)}</div>
    """
  end

  defp page(title, content) do
    """
    <!DOCTYPE html>
    <html lang="#{Gettext.get_locale(OrdoWeb.Gettext)}">
      <head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /><meta name="robots" content="noindex" /><title>#{title} · Ordo</title></head>
      <body style="margin:0;background:#f4f6f8;font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#16233b;">
        <div style="max-width:520px;margin:40px auto;padding:0 16px;">
          <div style="background:#fff;border:1px solid #e2e8f0;">
            <div style="padding:16px 24px;border-bottom:2px solid #16233b;font-family:'IBM Plex Mono',monospace;font-weight:600;letter-spacing:0.3em;">ORDO<span style="color:#b8860b;">.</span></div>
            <div style="padding:24px;">#{content}</div>
          </div>
        </div>
      </body>
    </html>
    """
  end

  defp esc(nil), do: ""

  defp esc(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
