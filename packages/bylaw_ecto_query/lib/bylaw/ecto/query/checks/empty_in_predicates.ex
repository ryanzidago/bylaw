defmodule Bylaw.Ecto.Query.Checks.EmptyInPredicates do
  @moduledoc """
  Validates that root `where` predicates do not rely on empty `in` lists.

  This catches filters whose candidate list is already known to contain no
  non-nil values.

  ## Examples

  Bad:

      ids = []

      Thing
      |> from(as: :thing)
      |> where([thing: thing], thing.id in ^ids)

  Why this is bad:

  The query can never match a row because the candidate list has no non-nil
  values. Running it still spends database work on a known-empty result.

  Better:

      if Enum.empty?(ids) do
        []
      else
        Thing
        |> from(as: :thing)
        |> where([thing: thing], thing.id in ^ids)
        |> Repo.all()
      end

  Why this is better:

  The caller uses a cheap application fast path and only queries the database
  when there are candidates to match.

  ## Notes

  This check only trusts supported root `in` predicates. It intentionally leaves
  broader contradictory business logic to `ConflictingWherePredicates`.

  Such queries usually have a cheaper fast path: return `[]` before calling the
  repo. This check is separate from
  `Bylaw.Ecto.Query.Checks.ConflictingWherePredicates` because an empty list is
  usually a missing fast path rather than contradictory business logic.

  The check is intentionally narrow. It evaluates root schema fields and only
  trusts direct `in` predicates in `AND` where expressions. `Ecto.Enum` fields
  are normalized through the schema enum mapping. `or_where` and `or`
  expressions are handled as separate branches and only rejected when every
  branch contains an empty `in` predicate. Fragments, subqueries, and non-root
  bindings are ignored.

  ## Options

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  ## Usage

  Add this module to the checks passed to `Bylaw.Ecto.Query.validate/3`.
  See the README usage section for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue
  alias Bylaw.Ecto.Query.RootWherePredicates

  @typedoc false
  @type comparable_value :: atom() | integer() | String.t()
  @typedoc false
  @type predicate :: %{
          field: atom(),
          operator: :in,
          values: list(comparable_value())
        }
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
    check_opts = CheckOptions.normalize!(opts, [:validate])

    if CheckOptions.enabled?(check_opts) do
      validate_enabled(operation, query)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_enabled(operation, query) do
    case Introspection.root_schema(query) do
      {:ok, schema} ->
        operation
        |> issues(RootWherePredicates.branches(query, schema))
        |> result()

      :unknown ->
        :ok
    end
  end

  defp issues(operation, predicate_branches) do
    branch_empty_predicates = Enum.map(predicate_branches, &empty_in_predicates/1)

    if Enum.any?(branch_empty_predicates, &Enum.empty?/1) do
      []
    else
      branch_empty_predicates
      |> List.flatten()
      |> Enum.uniq_by(&predicate_key/1)
      |> Enum.group_by(& &1.field)
      |> Enum.map(fn {field, predicates} -> issue(operation, field, predicates) end)
      |> Enum.sort_by(& &1.meta.field)
    end
  end

  defp empty_in_predicates(predicates) do
    Enum.filter(predicates, fn predicate ->
      predicate.operator == :in and Enum.empty?(predicate.values)
    end)
  end

  defp predicate_key(predicate), do: {predicate.field, predicate.operator, predicate.values}

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp issue(operation, field, predicates) do
    %Issue{
      check: __MODULE__,
      message: "expected in predicate on #{inspect(field)} to include at least one non-nil value",
      meta: %{
        operation: operation,
        field: field,
        predicates: Enum.map(predicates, &predicate_meta/1)
      }
    }
  end

  defp predicate_meta(predicate) do
    %{
      operator: predicate.operator,
      values: predicate.values
    }
  end
end
