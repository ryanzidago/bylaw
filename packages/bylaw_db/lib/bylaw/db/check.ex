defmodule Bylaw.Db.Check do
  @moduledoc """
  Behaviour implemented by database validation checks.

  A check receives one `t:Bylaw.Db.Target.t/0` and any check-specific options.
  Scope such as schemas, tables, or indexes belongs in the check options.
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
  Validates one database target.

  Return `:ok` when the target passes, or `{:error, issues}` with a non-empty
  list of `t:Bylaw.Db.Issue.t/0` values when it fails.
  """
  @callback validate(target :: Target.t(), opts :: check_opts()) :: result()
end
