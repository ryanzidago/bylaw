defmodule Bylaw.Ecto.Query.Check do
  @moduledoc """
  Behaviour for checks that validate an `Ecto.Query` before it runs.

  Every built-in check implements this callback contract. End users should
  usually call `Bylaw.Ecto.Query.validate/3` with an explicit check list instead
  of calling check modules directly.
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

  `:ok` means the query passed the check. `{:error, issues}` reports one or
  more query issues.
  """
  @type result :: :ok | {:error, nonempty_list(Issue.t())}

  @doc """
  Validates a prepared Ecto query for one check.
  """
  @callback validate(operation(), query(), opts()) :: result()
end
