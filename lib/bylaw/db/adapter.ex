defmodule Bylaw.Db.Adapter do
  @moduledoc """
  Behaviour for database adapters.

  Adapters own database-specific source construction and query execution. Checks
  stay isolated and call adapter functions when they need database internals.
  """

  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @typedoc """
  Raw database query result returned by an adapter.
  """
  @type query_result :: term()

  @doc """
  Builds a single validation target for this adapter.
  """
  @callback target(opts :: keyword()) :: Target.t()

  @doc """
  Runs `checks` against one target or a list of targets.
  """
  @callback validate(Target.t() | list(Target.t()), list(Bylaw.Db.check_spec())) ::
              Check.result()

  @doc """
  Executes database-specific introspection SQL for `target`.
  """
  @callback query(Target.t(), sql :: String.t(), params :: list(term()), opts :: keyword()) ::
              {:ok, query_result()} | {:error, term()}
end
