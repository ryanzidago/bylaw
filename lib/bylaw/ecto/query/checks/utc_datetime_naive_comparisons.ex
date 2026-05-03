defmodule Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisons do
  @moduledoc """
  Validates that root UTC datetime fields are not compared to `NaiveDateTime` values.

  This catches queries where a field backed by `:utc_datetime` or
  `:utc_datetime_usec` is compared to a `NaiveDateTime` value:

      naive_datetime = ~N[2026-01-01 00:00:00]

      from event in Event,
        where: event.inserted_at >= ^naive_datetime

  Ecto may be able to cast many values, but a naive datetime does not say what
  timezone the value meant. Callers should convert the value to a `DateTime`
  before building the query so the timezone decision is explicit.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [{Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisons, validate: false}])

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:fields` - optional non-empty list of root fields to validate. When
      omitted, the check validates UTC datetime fields reflected from the root
      Ecto schema.

  The check inspects direct root field comparisons and `in` predicates in
  `where` expressions. It detects visible `NaiveDateTime` values in pinned
  parameters, pinned lists, `type(^param, type)` wrappers, and supported raw
  query maps. It ignores field-to-field comparisons, non-root bindings,
  fragments that hide field access, subqueries, and schema-less queries without
  configured fields.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @comparison_operators [:==, :!=, :<, :<=, :>, :>=]
  @utc_datetime_types [:utc_datetime, :utc_datetime_usec]

  @type value_source :: :literal | :parameter | :tagged
  @type violation :: %{
          field: atom(),
          operator: atom(),
          value_source: value_source()
        }
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:fields, list(atom())}
          )
  @type opts :: check_opts()

  @doc """
  Validates UTC datetime comparisons for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same static
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate, :fields])

    if CheckOptions.enabled?(check_opts) do
      validate_enabled(operation, query, check_opts)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_enabled(operation, query, check_opts) do
    case checked_fields(query, check_opts) do
      [] ->
        :ok

      fields ->
        operation
        |> issues(query, fields)
        |> result()
    end
  end

  defp checked_fields(query, opts) do
    case {configured_fields(opts), Introspection.root_schema(query)} do
      {{:ok, fields}, {:ok, schema}} ->
        schema_fields = Introspection.schema_fields(schema)
        Enum.filter(fields, &MapSet.member?(schema_fields, &1))

      {{:ok, fields}, :unknown} ->
        fields

      {:infer, {:ok, schema}} ->
        utc_datetime_schema_fields(schema)

      {:infer, :unknown} ->
        []
    end
  end

  defp configured_fields(opts) do
    case Keyword.fetch(opts, :fields) do
      {:ok, fields} -> {:ok, normalize_fields!(fields)}
      :error -> :infer
    end
  end

  defp normalize_fields!(fields) when is_list(fields) do
    fields
    |> CheckOptions.non_empty_atoms!(:fields)
    |> Enum.uniq()
  end

  defp normalize_fields!(fields) do
    raise ArgumentError,
          "expected :fields to be a non-empty list of atoms, got: #{inspect(fields)}"
  end

  defp utc_datetime_schema_fields(schema) do
    schema.__schema__(:fields)
    |> Enum.filter(&utc_datetime_schema_field?(schema, &1))
    |> Enum.sort()
  end

  defp utc_datetime_schema_field?(schema, field) do
    schema
    |> schema_type(field)
    |> utc_datetime_type?()
  end

  defp schema_type(schema, field), do: schema.__schema__(:type, field)

  defp utc_datetime_type?(type), do: type in @utc_datetime_types

  defp issues(operation, query, fields) do
    query
    |> naive_comparison_violations(fields)
    |> Enum.group_by(& &1.field)
    |> Enum.map(fn {field, violations} -> issue(operation, field, violations) end)
    |> Enum.sort_by(& &1.meta.field)
  end

  defp naive_comparison_violations(query, fields) when is_map(query) do
    fields = MapSet.new(fields)
    root_aliases = Introspection.root_aliases(query)

    query
    |> Map.get(:wheres, [])
    |> Enum.flat_map(&violations_in_where(&1, fields, root_aliases))
  end

  defp naive_comparison_violations(_query, _fields), do: []

  defp violations_in_where(%{expr: expr} = where, fields, root_aliases) do
    params = Map.get(where, :params, [])

    violations_in_expr(expr, params, fields, root_aliases)
  end

  defp violations_in_where(_where, _fields, _root_aliases), do: []

  defp violations_in_expr({operator, _meta, [left, right]}, params, fields, root_aliases)
       when operator in [:and, :or] do
    violations_in_expr(left, params, fields, root_aliases) ++
      violations_in_expr(right, params, fields, root_aliases)
  end

  defp violations_in_expr({:not, _meta, [expr]}, params, fields, root_aliases) do
    violations_in_expr(expr, params, fields, root_aliases)
  end

  defp violations_in_expr({operator, _meta, [left, right]}, params, fields, root_aliases)
       when operator in @comparison_operators do
    comparison_violations(left, right, operator, params, fields, root_aliases)
  end

  defp violations_in_expr({:in, _meta, [left, right]}, params, fields, root_aliases) do
    in_violations(left, right, params, fields, root_aliases)
  end

  defp violations_in_expr(_expr, _params, _fields, _root_aliases), do: []

  defp comparison_violations(left, right, operator, params, fields, root_aliases) do
    case {checked_root_field(left, fields, root_aliases),
          checked_root_field(right, fields, root_aliases)} do
      {{:ok, field}, _right_field} ->
        value_violations(field, operator, right, params)

      {:error, {:ok, field}} ->
        value_violations(field, reverse_operator(operator), left, params)

      {:error, :error} ->
        []
    end
  end

  defp in_violations(left, right, params, fields, root_aliases) do
    case checked_root_field(left, fields, root_aliases) do
      {:ok, field} -> value_violations(field, :in, right, params)
      :error -> []
    end
  end

  defp checked_root_field(expr, fields, root_aliases) do
    case Introspection.direct_root_field(expr, root_aliases) do
      {:ok, field} -> checked_field(fields, field)
      :unknown -> :error
    end
  end

  defp checked_field(fields, field) when is_atom(field) do
    if MapSet.member?(fields, field), do: {:ok, field}, else: :error
  end

  defp checked_field(fields, field) when is_binary(field) do
    case Enum.find(fields, &(Atom.to_string(&1) == field)) do
      nil -> :error
      matched_field -> {:ok, matched_field}
    end
  end

  defp value_violations(field, operator, expr, params) do
    if Introspection.field_reference?(expr) do
      []
    else
      case naive_datetime_source(expr, params) do
        {:ok, source} ->
          [
            %{
              field: field,
              operator: operator,
              value_source: source
            }
          ]

        :error ->
          []
      end
    end
  end

  defp naive_datetime_source(%NaiveDateTime{}, _params), do: {:ok, :literal}

  defp naive_datetime_source(%Ecto.Query.Tagged{value: value}, _params) do
    if contains_naive_datetime?(value), do: {:ok, :tagged}, else: :error
  end

  defp naive_datetime_source({:^, _meta, [index]}, params) when is_integer(index) do
    case Enum.fetch(params, index) do
      {:ok, {value, _type}} ->
        if contains_naive_datetime?(value), do: {:ok, :parameter}, else: :error

      :error ->
        :error
    end
  end

  defp naive_datetime_source({:type, _meta, [expr, _type]}, params) do
    naive_datetime_source(expr, params)
  end

  defp naive_datetime_source(values, params) when is_list(values) do
    Enum.find_value(values, :error, fn value ->
      case naive_datetime_source(value, params) do
        {:ok, source} -> {:ok, source}
        :error -> false
      end
    end)
  end

  defp naive_datetime_source(_expr, _params), do: :error

  defp contains_naive_datetime?(%NaiveDateTime{}), do: true

  defp contains_naive_datetime?(%Ecto.Query.Tagged{value: value}) do
    contains_naive_datetime?(value)
  end

  defp contains_naive_datetime?(values) when is_list(values) do
    Enum.any?(values, &contains_naive_datetime?/1)
  end

  defp contains_naive_datetime?(_value), do: false

  defp reverse_operator(:==), do: :==
  defp reverse_operator(:!=), do: :!=
  defp reverse_operator(:<), do: :>
  defp reverse_operator(:<=), do: :>=
  defp reverse_operator(:>), do: :<
  defp reverse_operator(:>=), do: :<=

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
  defp result(issues), do: {:error, issues}

  defp issue(operation, field, violations) do
    violations =
      violations
      |> Enum.uniq_by(&{&1.operator, &1.value_source})
      |> Enum.sort_by(&{&1.operator, &1.value_source})

    %Issue{
      check: __MODULE__,
      message:
        "expected UTC datetime field #{inspect(field)} to be compared with DateTime values, got NaiveDateTime",
      meta: %{
        operation: operation,
        field: field,
        violations: Enum.map(violations, &violation_meta/1)
      }
    }
  end

  defp violation_meta(violation) do
    %{
      operator: violation.operator,
      value_type: :naive_datetime,
      value_source: violation.value_source
    }
  end
end
