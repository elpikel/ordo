defmodule Ordo.Repo.Migrations.FixDemoDraftSignatures do
  use Ecto.Migration

  # The seeded demo draft replies embed the shop signature at generation time, so
  # existing drafts still close with the old "Zespół OneDayMore". Rewrite them to
  # the new "Zespół Ordo". Plain-text column (tickets.draft), no Cloak fields —
  # safe under release migrations. Reversible. (A fresh "Importuj skrzynkę" already
  # regenerates drafts with the current signature; this fixes rows seeded before.)
  @from "Zespół OneDayMore"
  @to "Zespół Ordo"

  def up do
    swap(@from, @to)
  end

  def down do
    swap(@to, @from)
  end

  defp swap(from, to) do
    execute("""
    UPDATE tickets SET draft = replace(draft, '#{from}', '#{to}')
    WHERE draft LIKE '%#{from}%'
    """)
  end
end
