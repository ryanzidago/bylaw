defmodule Bylaw.Db.Check do
  @moduledoc """
  Behaviour for checks that validate database internals.

  Database checks receive a single `t:Bylaw.Db.Target.t/0`. A target represents
  one adapter/database query source, so checks can stay narrow and avoid
  discovering their own execution context.
  """

  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @typedoc """
  The result returned by a database check.
  """
  @type result :: :ok | {:error, list(Issue.t())}

  @typedoc """
  Check-specific option.
  """
  @type check_opt :: {atom(), term()}

  @typedoc """
  Check-specific options.
  """
  @type check_opts :: list(check_opt())

  @doc """
  Returns the option namespace used by this check.
  """
  @callback name() :: atom()

  @doc """
  Validates a database target.

  Return `:ok` when the target passes, or `{:error, issues}` with a non-empty
  list of issues when it fails.
  """
  @callback validate(target :: Target.t(), opts :: check_opts()) :: result()
end
