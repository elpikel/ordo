defmodule Ordo.Support.Mailbox do
  @moduledoc """
  A tenant's email mailbox connection — the source Ordo polls (see CONTEXT.md:
  Mailbox connection). Holds the IMAP/SMTP connection, the encrypted password, and
  the polling cursor. A tenant has_many mailboxes (usually one).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ordo.Support.Tenant

  schema "mailboxes" do
    field :auth_strategy, :string, default: "imap_password"
    field :email, :string

    field :imap_host, :string
    field :imap_port, :integer, default: 993
    field :username, :string
    field :password, Ordo.Encrypted.Binary, redact: true

    field :smtp_host, :string
    field :smtp_port, :integer, default: 587

    field :folder, :string, default: "INBOX"

    field :uidvalidity, :integer
    field :last_uid, :integer, default: 0

    field :active, :boolean, default: true
    field :last_polled_at, :utc_datetime_usec
    field :last_error, :string

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [
      :tenant_id,
      :auth_strategy,
      :email,
      :imap_host,
      :imap_port,
      :username,
      :password,
      :smtp_host,
      :smtp_port,
      :folder,
      :active
    ])
    |> validate_required([:tenant_id, :email, :auth_strategy])
    |> validate_inclusion(:auth_strategy, ["imap_password", "oauth_gmail", "oauth_graph"])
  end

  @doc "Persist the polling cursor after a successful fetch."
  def cursor_changeset(mailbox, attrs) do
    cast(mailbox, attrs, [:uidvalidity, :last_uid, :last_polled_at, :last_error])
  end
end
