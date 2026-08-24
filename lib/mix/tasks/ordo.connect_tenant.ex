defmodule Mix.Tasks.Ordo.ConnectTenant do
  @shortdoc "Connect a real tenant to a BaseLinker account"
  @moduledoc """
  Create or update a non-demo tenant wired to a real BaseLinker account.

      mix ordo.connect_tenant <slug> <bl_token> [name] [support_email]

  The token is stored encrypted at rest (Cloak). The tenant uses the real
  BaseLinker HTTP adapter (demo: false), so processing its tickets hits the
  live API. Run again with the same slug to update the token/details.

  ## Examples

      mix ordo.connect_tenant acme "BL-TOKEN-xxx"
      mix ordo.connect_tenant acme "BL-TOKEN-xxx" "Acme Foods" bok@acme.pl
  """
  use Mix.Task

  alias Ordo.Repo
  alias Ordo.Support.Tenant

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {slug, token, name, email} = parse(args)

    attrs = %{
      slug: slug,
      name: name || slug,
      support_email: email,
      signature: "Zespół #{name || slug}",
      demo: false,
      bl_token: token
    }

    struct = Repo.get_by(Tenant, slug: slug) || %Tenant{}

    case struct |> Tenant.changeset(attrs) |> Repo.insert_or_update() do
      {:ok, t} ->
        Mix.shell().info("✓ Tenant '#{t.slug}' (#{t.name}) connected to BaseLinker — id=#{t.id}, demo=false.")
        Mix.shell().info("  Token stored encrypted. Add its Policy rules separately (from the audit).")

      {:error, changeset} ->
        Mix.raise("Failed to connect tenant: #{inspect(changeset.errors)}")
    end
  end

  defp parse([slug, token | rest]) when byte_size(slug) > 0 and byte_size(token) > 0 do
    case rest do
      [name, email | _] -> {slug, token, name, email}
      [name] -> {slug, token, name, nil}
      [] -> {slug, token, nil, nil}
    end
  end

  defp parse(_) do
    Mix.raise("Usage: mix ordo.connect_tenant <slug> <bl_token> [name] [support_email]")
  end
end
