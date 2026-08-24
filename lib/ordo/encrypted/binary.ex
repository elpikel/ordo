defmodule Ordo.Encrypted.Binary do
  @moduledoc "Ecto type for a value encrypted at rest via Ordo.Vault."
  use Cloak.Ecto.Binary, vault: Ordo.Vault
end
