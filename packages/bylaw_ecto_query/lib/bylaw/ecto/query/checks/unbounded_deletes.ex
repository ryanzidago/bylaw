defmodule Bylaw.Ecto.Query.Checks.UnboundedDeletes do
  @moduledoc """
  Validates that `delete_all` queries are bounded.

  This check prevents accidental table-wide deletes by requiring callers to add
  a restricting root `where` or `or_where` before `Repo.delete_all/2` runs.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  ## Examples

  Bad:

      from session in Session

  Why this is bad:

  A `delete_all` query without a root predicate can remove every row in the
  table.

  Better:

      from session in Session,
        where: session.expires_at < ^DateTime.utc_now()

  Why this is better:

  The root `where` clause states the intended delete scope.

  Limitations:

  This check only requires a non-true root predicate. It does not prove the
  predicate is selective or semantically correct.

  The check only validates the root query prepared for the `:delete_all`
  operation. It requires every possible root `where` branch to include at least
  one non-true expression and does not try to prove whether that
  predicate is selective.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Boundedness
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()

  @doc """
  Validates that `:delete_all` operations are bounded.

  Non-delete operations always pass. For delete operations, every possible root
  `where` or `or_where` branch must include a clause other than a `true`
  expression.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate])

    if CheckOptions.enabled?(check_opts) and unbounded_delete?(operation, query) do
      {:error, [issue(operation)]}
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp unbounded_delete?(:delete_all, query), do: not Boundedness.root_where_bounded?(query)
  defp unbounded_delete?(_operation, _query), do: false

  @spec issue(Bylaw.Ecto.Query.Check.operation()) :: Issue.t()
  defp issue(operation) do
    %Issue{
      check: __MODULE__,
      message: "expected delete_all query to include at least one non-true root where clause",
      meta: %{
        operation: operation
      }
    }
  end
end
