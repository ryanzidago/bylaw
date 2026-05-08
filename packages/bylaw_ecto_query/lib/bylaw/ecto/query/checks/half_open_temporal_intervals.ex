defmodule Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals do
  @moduledoc """
  Validates that root temporal interval predicates are half-open.

  Half-open temporal intervals include the start boundary and exclude the end
  boundary.

  ## Examples

  Inclusive end bounds can double-count records that sit exactly on a boundary:

      # Bad: the end boundary is inclusive.
      from event in Event,
        where: event.occurred_at > ^start_at,
        where: event.occurred_at <= ^end_at

  Use `>=` for the lower bound and `<` for the upper bound:

      # Better: [start_at, end_at) composes without overlap.
      from event in Event,
        where: event.occurred_at >= ^start_at,
        where: event.occurred_at < ^end_at

  This catches the common off-by-one interval boundary shapes `>` for a lower
  bound and `<=` for an upper bound on root temporal fields.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:fields` - optional non-empty list of root fields to validate. When
      omitted, the check validates temporal fields reflected from the root Ecto
      schema.

  The check is static. It inspects direct root field comparisons in `where`
  expressions and ignores field-to-field comparisons, non-root bindings,
  fragments that hide field access, and schema-less queries without configured
  fields.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @comparison_operators [:<, :<=, :>, :>=]
  @temporal_types [
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
  @type opts :: check_opts()

  @doc """
  Validates half-open temporal intervals for a prepared Ecto query.

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
        temporal_schema_fields(schema)

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

  defp temporal_schema_fields(schema) do
    schema.__schema__(:fields)
    |> Enum.filter(&temporal_schema_field?(schema, &1))
    |> Enum.sort()
  end

  defp temporal_schema_field?(schema, field) do
    schema
    |> schema_type(field)
    |> temporal_type?()
  end

  defp schema_type(schema, field), do: schema.__schema__(:type, field)

  defp temporal_type?(type), do: type in @temporal_types

  defp issues(operation, query, fields) do
    query
    |> boundary_violations(fields)
    |> Enum.group_by(& &1.field)
    |> Enum.map(fn {field, violations} -> issue(operation, field, violations) end)
    |> Enum.sort_by(& &1.meta.field)
  end

  defp boundary_violations(query, fields) when is_map(query) do
    fields = MapSet.new(fields)
    root_aliases = Introspection.root_aliases(query)

    query
    |> Map.get(:wheres, [])
    |> Enum.flat_map(&boundary_violations_in_where(&1, fields, root_aliases))
  end

  defp boundary_violations(_query, _fields), do: []

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

  defp field_violation(field, other_expr, operator) do
    if Introspection.field_reference?(other_expr) do
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

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp issue(operation, field, violations) do
    %Issue{
      check: __MODULE__,
      message:
        "expected half-open temporal interval predicates on #{inspect(field)} to use >= for starts and < for ends",
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
