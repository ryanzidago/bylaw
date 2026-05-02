defmodule Bylaw.Ecto.Query.Checks.DateTimeBoundaries do
  @moduledoc """
  Validates that root date/time range predicates use half-open boundaries.

  Half-open ranges include the start boundary and exclude the end boundary:

      from event in Event,
        where: event.occurred_at >= ^start_at,
        where: event.occurred_at < ^end_at

  This catches the common off-by-one boundary shapes `>` for a lower bound and
  `<=` for an upper bound on root date/time fields.

      @bylaw [
        date_time_boundaries: [
          fields: [:occurred_at]
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.DateTimeBoundaries.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [date_time_boundaries: [validate: false]])

  Supported options:

      [
        date_time_boundaries: [
          validate: true,
          fields: [:occurred_at]
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:fields` - optional non-empty list of root fields to validate. When
      omitted, the check validates date/time fields reflected from the root
      Ecto schema.

  The check is static. It inspects direct root field comparisons in `where`
  expressions and ignores field-to-field comparisons, non-root bindings,
  fragments that hide field access, and schema-less queries without configured
  fields.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @comparison_operators [:<, :<=, :>, :>=]
  @date_time_types [
    :date,
    :time,
    :time_usec,
    :naive_datetime,
    :naive_datetime_usec,
    :utc_datetime,
    :utc_datetime_usec
  ]

  @type boundary :: :lower | :upper
  @type boundary_violation :: %{
          boundary: boundary(),
          field: atom(),
          operator: atom(),
          expected_operator: atom()
        }
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:fields, list(atom())}
          )
  @type opts :: list({:date_time_boundaries, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :date_time_boundaries
  def name, do: :date_time_boundaries

  @doc """
  Validates half-open date/time boundaries for a prepared Ecto query.

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
        date_time_schema_fields(schema)

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

  defp date_time_schema_fields(schema) do
    schema.__schema__(:fields)
    |> Enum.filter(&date_time_schema_field?(schema, &1))
    |> Enum.sort()
  end

  defp date_time_schema_field?(schema, field) do
    schema
    |> schema_type(field)
    |> date_time_type?()
  end

  defp schema_type(schema, field), do: schema.__schema__(:type, field)

  defp date_time_type?(type), do: type in @date_time_types

  defp issues(operation, query, fields) do
    query
    |> boundary_violations(fields)
    |> Enum.group_by(& &1.field)
    |> Enum.map(fn {field, violations} -> issue(operation, field, violations) end)
    |> Enum.sort_by(& &1.meta.field)
  end

  defp boundary_violations(query, fields) when is_map(query) do
    fields = MapSet.new(fields)
    root_aliases = root_aliases(query)

    query
    |> Map.get(:wheres, [])
    |> Enum.flat_map(&boundary_violations_in_where(&1, fields, root_aliases))
  end

  defp boundary_violations(_query, _fields), do: []

  defp root_aliases(query) do
    query
    |> Map.get(:aliases, %{})
    |> Enum.flat_map(fn
      {alias_name, 0} -> [alias_name]
      _alias -> []
    end)
    |> MapSet.new()
  end

  defp boundary_violations_in_where(%{expr: expr}, fields, root_aliases) do
    boundary_violations_in_expr(expr, fields, root_aliases)
  end

  defp boundary_violations_in_where(_where, _fields, _root_aliases), do: []

  defp boundary_violations_in_expr({operator, _meta, [left, right]}, fields, root_aliases)
       when operator in [:and, :or] do
    boundary_violations_in_expr(left, fields, root_aliases) ++
      boundary_violations_in_expr(right, fields, root_aliases)
  end

  defp boundary_violations_in_expr({operator, _meta, [left, right]}, fields, root_aliases)
       when operator in @comparison_operators do
    comparison_violation(left, right, operator, fields, root_aliases)
  end

  defp boundary_violations_in_expr(_expr, _fields, _root_aliases), do: []

  defp comparison_violation(left, right, operator, fields, root_aliases) do
    case {checked_root_field(left, fields, root_aliases),
          checked_root_field(right, fields, root_aliases)} do
      {{:ok, field}, _right_field} ->
        field
        |> field_violation(right, operator)
        |> List.wrap()

      {:error, {:ok, field}} ->
        field
        |> field_violation(left, reverse_operator(operator))
        |> List.wrap()

      {:error, :error} ->
        []
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

  defp field_violation(field, other_expr, operator) do
    if field_reference?(other_expr) do
      nil
    else
      violation(field, operator)
    end
  end

  defp violation(field, :>) do
    %{
      boundary: :lower,
      field: field,
      operator: :>,
      expected_operator: :>=
    }
  end

  defp violation(field, :<=) do
    %{
      boundary: :upper,
      field: field,
      operator: :<=,
      expected_operator: :<
    }
  end

  defp violation(_field, _operator), do: nil

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
    %Issue{
      check: __MODULE__,
      message:
        "expected date/time boundaries on #{inspect(field)} to use >= for starts and < for ends",
      meta: %{
        operation: operation,
        field: field,
        violations: Enum.map(violations, &violation_meta/1)
      }
    }
  end

  defp violation_meta(violation) do
    %{
      boundary: violation.boundary,
      operator: violation.operator,
      expected_operator: violation.expected_operator
    }
  end
end
