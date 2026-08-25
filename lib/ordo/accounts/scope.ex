defmodule Ordo.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Ordo.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Ordo.Accounts.User
  alias Ordo.Repo

  defstruct user: nil, tenant: nil

  @doc """
  Creates a scope for the given user.

  The user is preloaded with its `:tenant` so `current_scope.tenant` is always
  available for a logged-in user (see ADR-0010: tenant isolation by construction).

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    user = Repo.preload(user, :tenant)
    %__MODULE__{user: user, tenant: user.tenant}
  end

  def for_user(nil), do: nil
end
