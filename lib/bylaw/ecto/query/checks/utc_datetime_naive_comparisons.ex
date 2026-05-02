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

      @bylaw [
        utc_datetime_naive_comparisons: []
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisons.validate(
               operation,
               query,
               bylaw_opts
             ) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [utc_datetime_naive_comparisons: [validate: false]])

  Supported options:

      [
        utc_datetime_naive_comparisons: [
          validate: true,
          fields: [:inserted_at]
        ]
      ]

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
  @type opts :: list({:utc_datetime_naive_comparisons, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :utc_datetime_naive_comparisons
  def name, do: :utc_datetime_naive_comparisons

  @doc """
  Validates UTC datetime comparisons for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same static
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    if enabled?(check_opts) do
      validate_enabled(operation, query, check_opts)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp check_opts!(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> Keyword.get(name(), [])
      |> normalize_check_opts!()
    else
      raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_check_opts!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Enum.each(opts, &validate_check_opt!/1)
      opts
    else
      raise ArgumentError,
            "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_check_opts!(opts) do
    raise ArgumentError,
          "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_check_opt!({:validate, _value}), do: :ok
  defp validate_check_opt!({:fields, fields}), do: normalize_fields!(fields)

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

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
    case {configured_fields(opts), root_schema(query)} do
      {{:ok, fields}, {:ok, schema}} ->
        schema_fields = MapSet.new(schema.__schema__(:fields))
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

  defp normalize_fields!([]) do
    raise ArgumentError,
          "expected :fields to be a non-empty list of atoms, got: []"
  end

  defp normalize_fields!(fields) when is_list(fields) do
    fields
    |> Enum.map(&normalize_field!/1)
    |> Enum.uniq()
  end

  defp normalize_fields!(fields) do
    raise ArgumentError,
          "expected :fields to be a non-empty list of atoms, got: #{inspect(fields)}"
  end

  defp normalize_field!(field) when is_atom(field), do: field

  defp normalize_field!(field) do
    raise ArgumentError,
          "expected :fields to contain only atoms, got: #{inspect(field)}"
  end

  defp root_schema(%{from: %{source: {_source, schema}}})
       when is_atom(schema) and not is_nil(schema) do
    if function_exported?(schema, :__schema__, 1) do
      {:ok, schema}
    else
      :unknown
    end
  end

  defp root_schema(_query), do: :unknown

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
    root_aliases = root_aliases(query)

    query
    |> Map.get(:wheres, [])
    |> Enum.flat_map(&violations_in_where(&1, fields, root_aliases))
  end

  defp naive_comparison_violations(_query, _fields), do: []

  defp root_aliases(query) do
    query
    |> Map.get(:aliases, %{})
    |> Enum.flat_map(fn
      {alias_name, 0} -> [alias_name]
      _alias -> []
    end)
    |> MapSet.new()
  end

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
    case direct_root_field(expr, root_aliases) do
      {:ok, field} -> checked_field(fields, field)
      :error -> :error
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
    if field_reference?(expr) do
      []
    else
      expr
      |> naive_datetime_source(params)
      |> case do
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

  defp direct_root_field({:type, _meta, [expr, _type]}, root_aliases) do
    direct_root_field(expr, root_aliases)
  end

  defp direct_root_field({{:., _meta, [source, field]}, _call_meta, []}, root_aliases)
       when is_atom(field) or is_binary(field) do
    if root_binding?(source, root_aliases) do
      {:ok, field}
    else
      :error
    end
  end

  defp direct_root_field({:field, _meta, [source, field]}, root_aliases)
       when is_atom(field) or is_binary(field) do
    if root_binding?(source, root_aliases) do
      {:ok, field}
    else
      :error
    end
  end

  defp direct_root_field(_expr, _root_aliases), do: :error

  defp field_reference?({{:., _meta, [_source, field]}, _call_meta, []})
       when is_atom(field) or is_binary(field),
       do: true

  defp field_reference?({:field, _meta, [_source, field]})
       when is_atom(field) or is_binary(field),
       do: true

  defp field_reference?(expr) when is_tuple(expr) do
    expr
    |> Tuple.to_list()
    |> field_reference?()
  end

  defp field_reference?(expr) when is_list(expr), do: Enum.any?(expr, &field_reference?/1)
  defp field_reference?(_expr), do: false

  defp root_binding?({:&, _meta, [0]}, _root_aliases), do: true

  defp root_binding?({:as, _meta, [alias_name]}, root_aliases) when is_atom(alias_name) do
    MapSet.member?(root_aliases, alias_name)
  end

  defp root_binding?(_expr, _root_aliases), do: false

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
