defmodule Ordo.Vault do
  @moduledoc """
  Cloak vault for encrypting secrets at rest (e.g. tenant BaseLinker tokens).

  Cipher config is set per environment: dev/test keys live in `config/dev.exs`
  and `config/test.exs`; production reads `CLOAK_KEY` from the environment in
  `config/runtime.exs` and refuses to boot without it.
  """
  use Cloak.Vault, otp_app: :ordo
end
