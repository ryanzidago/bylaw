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
  @type result :: :ok | {:error, Issue.t() | list(Issue.t())}

  @doc """
  Returns the option namespace used by this check.
  """
  @callback name() :: atom()

  @doc """
  Validates a database target.
  """
  @callback validate(Target.t(), opts :: keyword()) :: result()
end
