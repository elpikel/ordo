defmodule Ordo.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ordo

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Create (or refresh) the seeded demo tenant + its Policy. Idempotent.
  Run on prod with: `bin/ordo eval "Ordo.Release.setup_demo()"`.
  """
  def setup_demo do
    load_app()

    {:ok, tenant, _} =
      Ecto.Migrator.with_repo(Ordo.Repo, fn _repo ->
        Ordo.Support.ensure_demo_tenant!()
      end)

    IO.puts("Demo tenant ready: slug=#{tenant.slug} name=#{tenant.name} (#{length(tenant.policy_facts)} rules).")
    IO.puts("Open it at /#{tenant.slug}/inbox")
    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
