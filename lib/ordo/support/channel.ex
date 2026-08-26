defmodule Ordo.Support.Channel do
  @moduledoc """
  A source Ordo hears customers on (ADR-0011): an email mailbox, a Google
  Business Profile, … A tenant has_many channels. Email channels carry the
  IMAP/SMTP connection, the encrypted password, and the polling cursor; other
  types keep their type-specific settings in `config`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ordo.Support.Tenant
  alias Ordo.Support.Ticket

  schema "channels" do
    field :type, :string, default: "email"
    field :name, :string
    field :config, :map, default: %{}

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
    has_many :tickets, Ticket

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :tenant_id,
      :type,
      :name,
      :config,
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
    |> validate_required([:tenant_id, :type])
    |> validate_inclusion(:type, ["email", "gbp"])
    |> validate_email_channel()
  end

  # Email channels are identified by their address and connection strategy;
  # other types (gbp, …) need neither.
  defp validate_email_channel(changeset) do
    if get_field(changeset, :type) == "email" do
      changeset
      |> validate_required([:email, :auth_strategy])
      |> validate_inclusion(:auth_strategy, ["imap_password", "oauth_gmail", "oauth_graph"])
    else
      changeset
    end
  end

  @doc "Persist the polling cursor after a successful fetch."
  def cursor_changeset(channel, attrs) do
    cast(channel, attrs, [:uidvalidity, :last_uid, :last_polled_at, :last_error])
  end
end
