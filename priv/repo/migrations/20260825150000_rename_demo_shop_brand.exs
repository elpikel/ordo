defmodule Ordo.Repo.Migrations.RenameDemoShopBrand do
  use Ecto.Migration

  # Rebrand the seeded demo shop from "OneDayMore" to "Ordo Demo". Plain-text
  # tenants columns only (name, signature) — no Cloak fields — so this is safe
  # under release migrations. Reversible.
  def up do
    execute(
      "UPDATE tenants SET name = 'Ordo Demo', signature = 'Zespół Ordo' WHERE slug = 'demo'"
    )
  end

  def down do
    execute(
      "UPDATE tenants SET name = 'OneDayMore', signature = 'Zespół OneDayMore' WHERE slug = 'demo'"
    )
  end
end
