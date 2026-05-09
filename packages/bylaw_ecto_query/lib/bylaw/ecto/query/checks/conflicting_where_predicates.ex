defmodule Bylaw.Ecto.Query.Checks.ConflictingWherePredicates do
  @moduledoc """
  Validates that root `where` predicates can all be satisfied.

  This catches impossible filters.

  ## Examples

  Bad:

      from post in Post,
        where: post.status == ^:draft,
        where: post.status == ^:published

  Why this is bad:

  No row can satisfy both equality predicates for the same field. The query is
  guaranteed to return no rows, which usually means a filter was composed
  incorrectly.

  Better:

      from post in Post,
        where: post.status in ^[:draft, :published]

  Why this is better:

  The allowed values are represented in one satisfiable predicate.

  Bad:

      from post in Post,
        where: post.sequence == ^1,
        where: post.sequence == ^2

  ## Notes

  This check is intentionally narrow. It evaluates supported root `where`
  predicates and ignores fragments, subqueries, non-root bindings, and most
  arbitrary expressions.

  The check is intentionally narrow. It evaluates root schema fields and only
  trusts direct `==`, `in`, and `is_nil` predicates in `AND` where expressions.
  `Ecto.Enum` fields are normalized through the schema enum mapping. Non-enum
  fields only compare simple literal values that already match the schema field
  type. `or_where` and `or` expressions are handled as separate branches and
  only rejected when every branch is statically unsatisfiable and at least one
  branch has a true predicate conflict. Fragments, subqueries, and non-root
  bindings are ignored. Empty `in` candidate lists can make a branch
  unsatisfiable, but standalone empty `in` issues are intentionally left to
  `Bylaw.Ecto.Query.Checks.EmptyInPredicates`.

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
  @type operator :: :== | :in | :is_nil
  @typedoc false
  @type predicate :: %{
          field: atom(),
          operator: operator(),
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
        |> issues(schema, RootWherePredicates.branches(query, schema))
        |> result()

      :unknown ->
        :ok
    end
  end

  defp issues(operation, schema, predicate_branches) do
    branch_results =
      Enum.map(predicate_branches, &branch_result(operation, schema, &1))

    if Enum.any?(branch_results, & &1.satisfiable?) do
      []
    else
      branch_results
      |> Enum.flat_map(& &1.issues)
      |> Enum.uniq_by(&issue_key/1)
      |> Enum.sort_by(&{&1.meta.field, inspect(&1.meta.predicates)})
    end
  end

  defp branch_result(operation, schema, predicates) do
    issues = issues_for_predicates(operation, schema, predicates)

    %{
      issues: issues,
      satisfiable?: Enum.empty?(issues) and not empty_in_predicate?(predicates)
    }
  end

  defp issues_for_predicates(operation, schema, predicates) do
    predicates
    |> Enum.group_by(& &1.field)
    |> Enum.flat_map(fn {field, field_predicates} ->
      field_predicates = Enum.reject(field_predicates, &Enum.empty?(&1.values))

      if conflicting?(field_predicates) do
        [issue(operation, schema, field, field_predicates)]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.meta.field)
  end

  defp empty_in_predicate?(predicates) do
    Enum.any?(predicates, fn predicate ->
      predicate.operator == :in and Enum.empty?(predicate.values)
    end)
  end

  defp issue_key(issue) do
    {
      issue.meta.field,
      Enum.map(issue.meta.predicates, &{&1.operator, &1.values})
    }
  end

  defp conflicting?(predicates) do
    case predicates do
      [_first, _second | _rest] = predicates ->
        predicates
        |> Enum.map(&MapSet.new(&1.values))
        |> intersection()
        |> Enum.empty?()

      _predicates ->
        false
    end
  end

  defp intersection([first | rest]), do: Enum.reduce(rest, first, &MapSet.intersection/2)

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp issue(operation, schema, field, predicates) do
    %Issue{
      check: __MODULE__,
      message: "expected where predicates on #{inspect(field)} to agree on a value",
      meta: issue_meta(operation, schema, field, predicates)
    }
  end

  defp issue_meta(operation, schema, field, predicates) do
    meta = %{
      operation: operation,
      field: field,
      predicates: Enum.map(predicates, &predicate_meta/1)
    }

    if enum_field?(schema, field) do
      Map.put(meta, :enum_values, Ecto.Enum.values(schema, field))
    else
      meta
    end
  end

  defp enum_field?(schema, field) do
    schema
    |> schema_type(field)
    |> Ecto.Type.parameterized?(Ecto.Enum)
  end

  defp schema_type(schema, field), do: schema.__schema__(:type, field)

  defp predicate_meta(predicate) do
    %{
      operator: predicate.operator,
      values: predicate.values
    }
  end
end
