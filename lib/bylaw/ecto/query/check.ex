defmodule Bylaw.Ecto.Query.Check do
  @moduledoc """
  Behaviour for checks that validate an `Ecto.Query` before it runs.

  Checks are intentionally small and directly callable so callers can decide how
  to compose them in `c:Ecto.Repo.prepare_query/3`.
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
  Bylaw options passed to the check.

  Checks should read their own nested options from this keyword list using
  their `name/0`.
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
  Returns the option namespace used by this check.

  The returned atom should match the key the check reads from `opts/0`.
  """
  @callback name() :: atom()

  @doc """
  Validates a prepared Ecto query.

  Return `:ok` when the query passes, or `{:error, issue}` /
  `{:error, issues}` when the check rejects it.
  """
  @callback validate(operation(), query(), opts()) :: result()
end
