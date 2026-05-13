defmodule Bylaw.Ecto.Query.Checks.UnboundedDeletes do
  @moduledoc """
  Validates that `delete_all` queries are bounded.

  This check prevents accidental table-wide deletes by requiring callers to add
  a restricting root `where` or `or_where` before `Repo.delete_all/2` runs.

  ## Examples

  Bad:

      from(Session, as: :session)

  Why this is bad:

  A `delete_all` query without a root predicate can remove every row in the
  table.

  Better:

      from(Session, as: :session)
      |> where([session: s], s.expires_at < ^DateTime.utc_now())

  Why this is better:

  The root `where` clause states the intended delete scope.

  ## Notes

  This check only requires a non-true root predicate. It does not prove the
  predicate is selective or semantically correct.

  The check only validates the root query prepared for the `:delete_all`
  operation. It requires every possible root `where` branch to include at least
  one non-true expression and does not try to prove whether that
  predicate is selective.

  ## Options

    * `:validate` - explicit `false` disables this check. It can be used in the
      repo-wide check list or in call-site overrides passed to
      `Bylaw.Ecto.Query.validate/4`.

  Run globally with defaults:

      Bylaw.Ecto.Query.Checks.UnboundedDeletes

  Run only for matching rule scopes:

      {Bylaw.Ecto.Query.Checks.UnboundedDeletes,
       rules: [
         [where: [ecto_schemas: [Session]]],
         [where: [tables: ["sessions"]]]
       ]}

  This check has no check-specific rule options.

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.Ecto.Query`.
  See `Bylaw.Ecto.Query` for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Boundedness
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue
  alias Bylaw.Ecto.Query.RuleOptions

  @typedoc false
  @type check_opts :: list({:validate, boolean()})
  @typedoc false
  @type opts :: check_opts()

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate, :rules])

    if CheckOptions.enabled?(check_opts) and
         RuleOptions.scoped?(check_opts, :unbounded_deletes, operation, query) and
         unbounded_delete?(operation, query) do
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
