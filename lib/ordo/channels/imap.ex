defmodule Ordo.Channels.Fetcher.IMAP do
  @moduledoc """
  Minimal poll-based IMAP fetch over `:ssl` (ADR-0007): connect, LOGIN, SELECT,
  UID FETCH new messages by the stored cursor, close. Reads INBOX only (ADR-0008).

  Incremental: if the server's UIDVALIDITY matches the stored one, fetch
  `(last_uid + 1):*`; otherwise (first run or mailbox rebuilt) fetch a bounded
  recent window from UIDNEXT. Note IMAP's `n:*` returns the highest message when
  `n` exceeds it, so the last message may re-appear — Message-ID dedup handles it.

  Best-effort protocol code; verify against a real mailbox (e.g. Gmail app password).
  """
  @behaviour Ordo.Channels.Fetcher

  require Logger

  @timeout 20_000
  @refetch_window 50

  @impl true
  def fetch_new(mailbox) do
    with {:ok, sock} <- connect(mailbox),
         :ok <- login(sock, mailbox),
         {:ok, sel} <- select(sock, mailbox.folder || "INBOX") do
      messages = fetch(sock, start_uid(mailbox, sel))
      logout(sock)
      {:ok, %{uidvalidity: sel.uidvalidity, messages: messages}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp connect(mailbox) do
    host = String.to_charlist(mailbox.imap_host || "")
    opts = [:binary, active: false, verify: :verify_none]

    case :ssl.connect(host, mailbox.imap_port || 993, opts, @timeout) do
      {:ok, sock} ->
        {:ok, _greeting} = recv_line(sock)
        {:ok, sock}

      err ->
        err
    end
  end

  defp login(sock, mailbox) do
    send_cmd(sock, "LOGIN #{quote_str(mailbox.username)} #{quote_str(mailbox.password)}")

    case recv(sock) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp select(sock, folder) do
    send_cmd(sock, "SELECT #{quote_str(folder)}")

    case recv(sock) do
      {:ok, resp} ->
        {:ok, %{uidvalidity: int_after(resp, "UIDVALIDITY"), uidnext: int_after(resp, "UIDNEXT")}}

      err ->
        err
    end
  end

  defp fetch(sock, start_uid) do
    send_cmd(sock, "UID FETCH #{start_uid}:* (UID BODY.PEEK[])")

    case recv(sock) do
      {:ok, resp} -> parse_fetch(resp, [])
      {:error, _} -> []
    end
  end

  defp logout(sock) do
    send_cmd(sock, "LOGOUT")
    recv(sock)
    :ssl.close(sock)
  end

  defp start_uid(mailbox, %{uidvalidity: uv, uidnext: uidnext}) do
    if mailbox.uidvalidity == uv and is_integer(mailbox.last_uid) and mailbox.last_uid > 0 do
      mailbox.last_uid + 1
    else
      max(1, (uidnext || 1) - @refetch_window)
    end
  end

  defp parse_fetch(raw, acc) do
    case Regex.run(~r/UID (\d+) BODY\[\] \{(\d+)\}\r\n/, raw, return: :index) do
      [{m_start, m_len}, {uid_s, uid_l}, {len_s, len_l}] ->
        uid = raw |> binary_part(uid_s, uid_l) |> String.to_integer()
        len = raw |> binary_part(len_s, len_l) |> String.to_integer()
        body_start = m_start + m_len
        body = binary_part(raw, body_start, len)
        rest_start = body_start + len
        rest = binary_part(raw, rest_start, byte_size(raw) - rest_start)
        parse_fetch(rest, [%{uid: uid, raw: body} | acc])

      _ ->
        Enum.reverse(acc)
    end
  end

  defp send_cmd(sock, cmd), do: :ssl.send(sock, "A " <> cmd <> "\r\n")

  # Read a tagged response, literal-aware so a message body can't fake completion.
  defp recv(sock, acc \\ "") do
    if complete?(acc) do
      {:ok, acc}
    else
      case :ssl.recv(sock, 0, @timeout) do
        {:ok, data} -> recv(sock, acc <> data)
        err -> err
      end
    end
  end

  defp complete?(buf) do
    case :binary.match(buf, "\r\n") do
      :nomatch ->
        false

      {idx, 2} ->
        line = binary_part(buf, 0, idx)
        rest = binary_part(buf, idx + 2, byte_size(buf) - idx - 2)

        case literal_len(line) do
          nil -> completion_line?(line) or complete?(rest)
          len -> byte_size(rest) >= len and complete?(binary_part(rest, len, byte_size(rest) - len))
        end
    end
  end

  defp completion_line?(line) do
    String.starts_with?(line, "A OK") or String.starts_with?(line, "A NO") or
      String.starts_with?(line, "A BAD")
  end

  defp literal_len(line) do
    case Regex.run(~r/\{(\d+)\}$/, line) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp recv_line(sock, acc \\ "") do
    case :binary.match(acc, "\r\n") do
      {idx, 2} ->
        {:ok, binary_part(acc, 0, idx)}

      :nomatch ->
        case :ssl.recv(sock, 0, @timeout) do
          {:ok, data} -> recv_line(sock, acc <> data)
          err -> err
        end
    end
  end

  defp int_after(resp, keyword) do
    case Regex.run(~r/#{keyword} (\d+)/, resp) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp quote_str(s) do
    escaped = s |> to_string() |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
    "\"" <> escaped <> "\""
  end
end
