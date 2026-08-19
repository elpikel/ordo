defmodule Ordo.Repo do
  use Ecto.Repo,
    otp_app: :ordo,
    adapter: Ecto.Adapters.Postgres
end
