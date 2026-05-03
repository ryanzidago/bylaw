defmodule Bylaw.Ecto.Query.Checks.UnboundedDeletes do
  @moduledoc """
  Validates that `delete_all` queries are bounded.

  This check prevents accidental table-wide deletes by requiring callers to add
  a restricting root `where` or `or_where` before `Repo.delete_all/2` runs.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.delete_all(query, bylaw: [{Bylaw.Ecto.Query.Checks.UnboundedDeletes, validate: false}])

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

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
      {:error, issue(operation)}
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
