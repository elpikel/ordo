defmodule Ordo.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Ordo.Support.Tenant

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
    IO.puts("Open the public demo at /demo")
    :ok
  end

  @doc """
  Create a new Tenant, its pending owner User, and send the owner an invitation
  email. Run on prod with `bin/ordo eval`.

  This is the public entry point for onboarding a real customer. It:

    1. inserts a `Ordo.Support.Tenant` with the given `slug` and `name`;
    2. creates a pending, unconfirmed owner `Ordo.Accounts.User` scoped to that
       tenant (email only, no password);
    3. emails the owner an invitation containing a magic login link.

  ## Arguments

    * `slug` — the tenant's URL-safe identifier, unique across the system
      (e.g. `"acme"`). Routes are slug-less (ADR-0010); the slug is only an
      internal handle.
    * `name` — the human-readable shop name (e.g. `"Acme Foods"`).
    * `owner_email` — the email address of the tenant's owner. The invitation is
      sent here.

  ## What the owner receives

  An invitation email with a magic login link. Clicking it logs them in, confirms
  their account, and drops them into their tenant's inbox. They then set a
  password on the settings page so they can log in again later. Every session is
  automatically scoped to their tenant.

  ## Usage

      bin/ordo eval "Ordo.Release.create_tenant(\\"acme\\", \\"Acme Foods\\", \\"owner@acme.pl\\")"

  ## Resending an invitation

  If the owner loses the email, re-deliver it (no new user is created):

      bin/ordo eval "Ordo.Release.resend_invitation(\\"owner@acme.pl\\")"

  Note: sending email in production requires `BREVO_API_KEY` to be set.
  """
  def create_tenant(slug, name, owner_email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(Ordo.Repo, fn _repo ->
        {:ok, tenant} =
          %Tenant{}
          |> Tenant.changeset(%{slug: slug, name: name})
          |> Ordo.Repo.insert()

        {:ok, user} = Ordo.Accounts.create_tenant_user(tenant, owner_email)
        deliver_invite(user)
        {tenant, user}
      end)

    {tenant, user} = result
    IO.puts("Tenant ready: slug=#{tenant.slug} name=#{tenant.name}")
    IO.puts("Invitation sent to owner: #{user.email}")
    :ok
  end

  @doc """
  Re-deliver the invitation email to an existing (pending) user. Run on prod with
  `bin/ordo eval "Ordo.Release.resend_invitation(\\"owner@acme.pl\\")"`.
  """
  def resend_invitation(email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(Ordo.Repo, fn _repo ->
        case Ordo.Accounts.get_user_by_email(email) do
          nil ->
            :not_found

          user ->
            deliver_invite(user)
            user
        end
      end)

    case result do
      :not_found ->
        IO.puts("No user found for #{email}.")

      user ->
        IO.puts("Invitation re-sent to #{user.email}")
    end

    :ok
  end

  defp deliver_invite(user) do
    Ordo.Accounts.deliver_invitation(
      user,
      &(OrdoWeb.Endpoint.url() <> "/users/log-in/#{&1}")
    )
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
