defmodule Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisons do
  @moduledoc """
  Validates that date fields are not compared to datetime fields without explicit truncation.

  This catches queries where a field backed by `:date` is compared directly to
  a field backed by `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime`, or
  `:naive_datetime_usec`.

  ## Examples

  Bad:

      from event in Event,
        where: event.event_date <= event.inserted_at

  Why this is bad:

  PostgreSQL can implicitly cast across date and timestamp types. With UTC
  timestamp fields, that cast may depend on the database session timezone. The
  date boundary is not visible in the query.

  Better:

      from event in Event,
        where: event.event_date <= type(event.inserted_at, :date)

  Why this is better:

  The datetime side is explicitly treated as a date, so the boundary decision is
  visible to reviewers.

  ## Notes

  This check inspects supported direct field-to-field comparisons and `in`
  predicates. It ignores values, schema-less sources, hidden fragment access,
  and subqueries.

  ## Options

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check is static. It inspects direct field-to-field comparisons and `in`
  predicates in `where`, `having`, and direct join `on` predicates, reflecting
  field types from the root schema, direct explicit join schemas, and
  association join schemas when the owner binding schema is known. It detects
  dot field access, `field/2`, named bindings, dynamic predicates, and
  `type(field, :date)` wrappers used as explicit truncation. It ignores values,
  schema-less sources, fragments that hide field access, and subqueries.

  ## Usage

  Add this module to the checks passed to `Bylaw.Ecto.Query.validate/3`.
  See the README usage section for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @comparison_operators [:==, :!=, :<, :<=, :>, :>=]
  @datetime_types [:naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec]

  @typedoc false
  @type datetime_type ::
          :naive_datetime | :naive_datetime_usec | :utc_datetime | :utc_datetime_usec
  @typedoc false
  @type field_side :: %{
          binding_index: non_neg_integer(),
          field: atom(),
          schema: module(),
          schema_type: :date | datetime_type(),
          truncated_to_date?: boolean()
        }
  @typedoc false
  @type violation :: %{
          date_binding_index: non_neg_integer(),
          date_field: atom(),
          date_schema: module(),
          datetime_binding_index: non_neg_integer(),
          datetime_field: atom(),
          datetime_schema: module(),
          datetime_type: datetime_type(),
          operator: atom()
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
      operation
      |> issues(query)
      |> result()
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp issues(operation, query) do
    query
    |> Introspection.query_branches()
    |> Enum.flat_map(&issues_for_branch(operation, &1))
    |> Enum.sort_by(
      &{Map.get(&1.meta, :combination_path, []), &1.meta.date_binding_index, &1.meta.date_field}
    )
  end

  defp issues_for_branch(operation, {branch_path, query}) do
    query
    |> mixed_comparison_violations()
    |> Enum.group_by(&{&1.date_binding_index, &1.date_schema, &1.date_field})
    |> Enum.map(fn {{date_binding_index, date_schema, date_field}, violations} ->
      issue(operation, branch_path, date_binding_index, date_schema, date_field, violations)
    end)
  end

  defp mixed_comparison_violations(query) when is_map(query) do
    aliases = Introspection.aliases(query)
    schemas = binding_schemas(query)

    query
    |> predicate_exprs()
    |> Enum.flat_map(&violations_in_expr(&1, aliases, schemas))
  end

  defp mixed_comparison_violations(_query), do: []

  defp binding_schemas(query) do
    %{}
    |> put_root_schema(query)
    |> put_join_schemas(query)
  end

  defp put_root_schema(schemas, query) do
    case Introspection.root_schema(query) do
      {:ok, schema} -> Map.put(schemas, 0, schema)
      :unknown -> schemas
    end
  end

  defp put_join_schemas(schemas, %{joins: joins}) when is_list(joins) do
    joins
    |> Enum.with_index(1)
    |> Enum.reduce(schemas, fn {join, binding_index}, schemas ->
      case join_schema(join, schemas) do
        {:ok, schema} -> Map.put(schemas, binding_index, schema)
        :skip -> schemas
      end
    end)
  end

  defp put_join_schemas(schemas, _query), do: schemas

  defp join_schema(join, schemas) do
    case Introspection.explicit_join_schema(join) do
      {:ok, schema} -> {:ok, schema}
      :skip -> association_join_schema(join, schemas)
    end
  end

  defp association_join_schema(%{assoc: {owner_binding_index, assoc_name}}, schemas)
       when is_integer(owner_binding_index) and owner_binding_index >= 0 and is_atom(assoc_name) do
    with {:ok, owner_schema} <- Map.fetch(schemas, owner_binding_index),
         %{related: related_schema} <- owner_schema.__schema__(:association, assoc_name),
         true <- schema?(related_schema) do
      {:ok, related_schema}
    else
      _other -> :skip
    end
  end

  defp association_join_schema(_join, _schemas), do: :skip

  defp schema?(schema) when is_atom(schema) and not is_nil(schema) do
    function_exported?(schema, :__schema__, 1)
  end

  defp schema?(_schema), do: false

  defp predicate_exprs(query) do
    boolean_exprs(Map.get(query, :wheres, [])) ++
      boolean_exprs(Map.get(query, :havings, [])) ++
      join_on_exprs(Map.get(query, :joins, []))
  end

  defp boolean_exprs(exprs) when is_list(exprs) do
    Enum.flat_map(exprs, fn
      %{expr: expr} -> [expr]
      _expr -> []
    end)
  end

  defp boolean_exprs(_exprs), do: []

  defp join_on_exprs(joins) when is_list(joins) do
    Enum.flat_map(joins, fn
      %{on: %{expr: expr}} -> [expr]
      _join -> []
    end)
  end

  defp join_on_exprs(_joins), do: []

  defp violations_in_expr({operator, _meta, [left, right]}, aliases, schemas)
       when operator in [:and, :or] do
    violations_in_expr(left, aliases, schemas) ++ violations_in_expr(right, aliases, schemas)
  end

  defp violations_in_expr({:not, _meta, [expr]}, aliases, schemas) do
    violations_in_expr(expr, aliases, schemas)
  end

  defp violations_in_expr({operator, _meta, [left, right]}, aliases, schemas)
       when operator in @comparison_operators do
    left
    |> field_side(aliases, schemas)
    |> comparison_violation(field_side(right, aliases, schemas), operator)
    |> List.wrap()
  end

  defp violations_in_expr({:in, _meta, [left, right]}, aliases, schemas) do
    left_side = field_side(left, aliases, schemas)

    right
    |> in_candidates()
    |> Enum.flat_map(fn candidate ->
      left_side
      |> comparison_violation(field_side(candidate, aliases, schemas), :in)
      |> List.wrap()
    end)
  end

  defp violations_in_expr(_expr, _aliases, _schemas), do: []

  defp in_candidates(candidates) when is_list(candidates), do: candidates
  defp in_candidates(_candidates), do: []

  defp comparison_violation(left, right, operator) do
    case {left, right} do
      {{:ok, left}, {:ok, right}} -> mixed_field_violation(left, right, operator)
      _result -> nil
    end
  end

  defp mixed_field_violation(%{schema_type: :date} = date, datetime, operator) do
    if datetime_field_without_truncation?(datetime) do
      violation(date, datetime, operator)
    end
  end

  defp mixed_field_violation(datetime, %{schema_type: :date} = date, operator) do
    if datetime_field_without_truncation?(datetime) do
      violation(date, datetime, reverse_operator(operator))
    end
  end

  defp mixed_field_violation(_left, _right, _operator), do: nil

  defp datetime_field_without_truncation?(%{schema_type: type, truncated_to_date?: false}) do
    datetime_type?(type)
  end

  defp datetime_field_without_truncation?(_field), do: false

  defp field_side({:type, _meta, [expr, :date]}, aliases, schemas) do
    case field_side(expr, aliases, schemas) do
      {:ok, field_side} -> {:ok, %{field_side | truncated_to_date?: true}}
      :error -> :error
    end
  end

  defp field_side({:type, _meta, [expr, _type]}, aliases, schemas) do
    field_side(expr, aliases, schemas)
  end

  defp field_side(expr, aliases, schemas) do
    case Introspection.field(expr, aliases) do
      {:ok, {binding_index, field}} ->
        schema_field_side(binding_index, field, schemas)

      :unknown ->
        :error
    end
  end

  defp schema_field_side(binding_index, field, schemas) do
    with {:ok, schema} <- Map.fetch(schemas, binding_index),
         true <- Introspection.schema_field?(schema, field),
         schema_type when schema_type in [:date | @datetime_types] <-
           schema.__schema__(:type, field) do
      {:ok,
       %{
         binding_index: binding_index,
         field: field,
         schema: schema,
         schema_type: schema_type,
         truncated_to_date?: false
       }}
    else
      _other -> :error
    end
  end

  defp datetime_type?(type), do: type in @datetime_types

  defp reverse_operator(:==), do: :==
  defp reverse_operator(:!=), do: :!=
  defp reverse_operator(:<), do: :>
  defp reverse_operator(:<=), do: :>=
  defp reverse_operator(:>), do: :<
  defp reverse_operator(:>=), do: :<=
  defp reverse_operator(:in), do: :in

  defp violation(date, datetime, operator) do
    %{
      date_binding_index: date.binding_index,
      date_field: date.field,
      date_schema: date.schema,
      datetime_binding_index: datetime.binding_index,
      datetime_field: datetime.field,
      datetime_schema: datetime.schema,
      datetime_type: datetime.schema_type,
      operator: operator
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp issue(operation, branch_path, date_binding_index, date_schema, date_field, violations) do
    violations =
      violations
      |> Enum.uniq_by(&{&1.operator, &1.datetime_binding_index, &1.datetime_field})
      |> Enum.sort_by(&{&1.datetime_binding_index, &1.datetime_field, &1.operator})

    meta =
      Map.merge(
        %{
          operation: operation,
          date_schema: date_schema,
          date_binding_index: date_binding_index,
          date_field: date_field,
          violations: Enum.map(violations, &violation_meta/1)
        },
        Introspection.combination_path_meta(branch_path)
      )

    %Issue{
      check: __MODULE__,
      message:
        "expected date field #{inspect(date_field)} to compare with datetime fields only after explicit date truncation",
      meta: meta
    }
  end

  defp violation_meta(violation) do
    %{
      operator: violation.operator,
      datetime_schema: violation.datetime_schema,
      datetime_binding_index: violation.datetime_binding_index,
      datetime_field: violation.datetime_field,
      datetime_type: violation.datetime_type
    }
  end
end
