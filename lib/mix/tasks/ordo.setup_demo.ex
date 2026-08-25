defmodule Mix.Tasks.Ordo.SetupDemo do
  @shortdoc "Create/refresh the seeded demo tenant + Policy (dev)"
  @moduledoc """
  Create (or refresh) the seeded demo tenant and its Policy. Idempotent.

      mix ordo.setup_demo

  On production (a release, no Mix) use instead:

      bin/ordo eval "Ordo.Release.setup_demo()"
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    tenant = Ordo.Support.ensure_demo_tenant!()

    Mix.shell().info("Demo tenant ready: slug=#{tenant.slug} name=#{tenant.name} (#{length(tenant.policy_facts)} rules).")

    Mix.shell().info("Open it at /#{tenant.slug}/inbox")
  end
end
