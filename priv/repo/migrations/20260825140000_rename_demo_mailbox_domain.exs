defmodule Ordo.Repo.Migrations.RenameDemoMailboxDomain do
  use Ecto.Migration

  # Rebrand the seeded demo shop's addresses from @onedaymore.pl to @hireordo.com.
  # Plain-text columns only (mailboxes.email, tenants.support_email, the
  # contact_email policy fact) — no Cloak fields — so this is safe under release
  # migrations. Reversible.
  @from "@onedaymore.pl"
  @to "@hireordo.com"

  def up do
    swap_domain(@from, @to)
  end

  def down do
    swap_domain(@to, @from)
  end

  defp swap_domain(from, to) do
    execute("""
    UPDATE mailboxes SET email = replace(email, '#{from}', '#{to}')
    WHERE email LIKE '%#{from}'
    """)

    execute("""
    UPDATE tenants SET support_email = replace(support_email, '#{from}', '#{to}')
    WHERE support_email LIKE '%#{from}'
    """)

    execute("""
    UPDATE policy_facts SET value = replace(value, '#{from}', '#{to}')
    WHERE value LIKE '%#{from}'
    """)
  end
end
