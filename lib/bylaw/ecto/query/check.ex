defmodule Bylaw.Ecto.Query.Check do
  @moduledoc """
  Behaviour for checks that validate an `Ecto.Query` before it runs.

  Checks are intentionally small and directly callable. `Bylaw.Ecto.Query`
  composes them from module-based check specs for `c:Ecto.Repo.prepare_query/3`.

  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for the
  built-in check list, repo wiring, and option examples.
  """

  alias Bylaw.Ecto.Query.Issue

  @typedoc """
  The Ecto query operation being prepared.

  Ecto calls `c:Ecto.Repo.prepare_query/3` with these operations. Query helpers
  such as `Repo.one/2`, `Repo.get/3`, and `Repo.exists?/2` are prepared as
  `:all`.
  """
  @type operation :: :all | :update_all | :delete_all | :stream | :insert_all

  @typedoc """
  The query being validated before the repo runs it.
  """
  @type query :: Ecto.Query.t()

  @typedoc """
  Check-specific options passed to the check.
  """
  @type opts :: list({atom(), term()})

  @typedoc """
  The result returned by a query check.

  `:ok` means the query passed the check. `{:error, issue}` and
  `{:error, issues}` let each check decide whether it reports one issue or
  several issues.
  """
  @type result :: :ok | {:error, Issue.t() | list(Issue.t())}

  @doc """
  Validates a prepared Ecto query.

  Return `:ok` when the query passes, or `{:error, issue}` /
  `{:error, issues}` when the check rejects it.
  """
  @callback validate(operation(), query(), opts()) :: result()
end
