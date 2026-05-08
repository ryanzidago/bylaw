defmodule Bylaw.Db.Adapter do
  @moduledoc """
  Behaviour implemented by database adapter packages.

  Adapters build validation targets, run checks, and execute database-specific
  introspection queries for checks.
  """

  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @typedoc """
  Raw database query result returned by an adapter.
  """
  @type query_result :: term()

  @typedoc """
  Adapter-specific target construction option.
  """
  @type target_opt :: {atom(), term()}

  @typedoc """
  Adapter-specific target construction options.
  """
  @type target_opts :: list(target_opt())

  @typedoc """
  Adapter-specific query execution option.
  """
  @type query_opt :: {atom(), term()}

  @typedoc """
  Adapter-specific query execution options.
  """
  @type query_opts :: list(query_opt())

  @doc """
  Builds a single validation target from adapter-specific options.
  """
  @callback target(opts :: target_opts()) :: Target.t()

  @doc """
  Runs `checks` against a non-empty list of targets.

  Adapter implementations should usually delegate to `Bylaw.Db.validate/2`.
  """
  @callback validate(targets :: list(Target.t()), checks :: list(Bylaw.Db.check_spec())) ::
              Check.result()

  @doc """
  Executes database-specific introspection SQL for `target`.

  Checks call this callback through the target's adapter when they need database
  metadata.
  """
  @callback query(
              target :: Target.t(),
              sql :: String.t(),
              params :: list(term()),
              opts :: query_opts()
            ) :: {:ok, query_result()} | {:error, term()}
end
