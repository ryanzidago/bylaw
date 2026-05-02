defmodule Bylaw.Ecto.Query.Checks.ConflictingWherePredicates do
  @moduledoc """
  Validates that root `where` predicates can all be satisfied.

  This catches impossible filters such as:

      from post in Post,
        where: post.status == ^:draft,
        where: post.status == ^:published

      from post in Post,
        where: post.sequence == ^1,
        where: post.sequence == ^2

  The check is intentionally narrow. It evaluates root schema fields and only
  trusts direct `==`, `in`, and `is_nil` predicates in `AND` where expressions.
  `Ecto.Enum` fields are normalized through the schema enum mapping. Non-enum
  fields only compare simple literal values that already match the schema field
  type. `or_where` and `or` expressions are handled as separate branches and
  only rejected when every branch conflicts. Fragments, subqueries, and
  non-root bindings are ignored.

      @bylaw [
        conflicting_where_predicates: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.ConflictingWherePredicates.validate(
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

      Repo.all(query, bylaw: [conflicting_where_predicates: [validate: false]])

  Supported options:

      [
        conflicting_where_predicates: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type comparable_value :: atom() | integer() | String.t()
  @type operator :: :== | :in | :is_nil
  @type predicate :: %{
          field: atom(),
          operator: operator(),
          values: list(comparable_value())
        }
  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:conflicting_where_predicates, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :conflicting_where_predicates
  def name, do: :conflicting_where_predicates

  @doc """
  Validates that root `where` predicates are mutually satisfiable.

  The operation is kept as issue metadata. This check applies the same static
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    if enabled?(check_opts) do
      validate_enabled(operation, query)
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

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp validate_enabled(operation, query) do
    case root_schema(query) do
      {:ok, schema} ->
        operation
        |> issues(schema, where_predicate_branches(query, schema, root_aliases(query)))
        |> result()

      :unknown ->
        :ok
    end
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

  defp root_aliases(query) do
    query
    |> Map.get(:aliases, %{})
    |> Enum.flat_map(fn
      {alias_name, 0} -> [alias_name]
      _alias -> []
    end)
    |> MapSet.new()
  end

  defp where_predicate_branches(query, schema, root_aliases) when is_map(query) do
    query
    |> Map.get(:wheres, [])
    |> Enum.reduce(nil, fn where, branches ->
      where_branches = predicate_branches_in_where(where, schema, root_aliases)

      case Map.get(where, :op, :and) do
        :or -> concat_predicate_branches(branches, where_branches)
        _op -> merge_predicate_branches(branches, where_branches)
      end
    end)
    |> case do
      nil -> [[]]
      branches -> branches
    end
  end

  defp predicate_branches_in_where(%{expr: expr, params: params}, schema, root_aliases) do
    predicate_branches_in_expr(expr, params, schema, root_aliases)
  end

  defp predicate_branches_in_where(_where, _schema, _root_aliases), do: [[]]

  defp predicate_branches_in_expr({:and, _meta, [left, right]}, params, schema, root_aliases) do
    merge_predicate_branches(
      predicate_branches_in_expr(left, params, schema, root_aliases),
      predicate_branches_in_expr(right, params, schema, root_aliases)
    )
  end

  defp predicate_branches_in_expr({:or, _meta, [left, right]}, params, schema, root_aliases) do
    predicate_branches_in_expr(left, params, schema, root_aliases) ++
      predicate_branches_in_expr(right, params, schema, root_aliases)
  end

  defp predicate_branches_in_expr({:==, _meta, [left, right]}, params, schema, root_aliases) do
    [equality_predicates(left, right, params, schema, root_aliases)]
  end

  defp predicate_branches_in_expr({:in, _meta, [left, right]}, params, schema, root_aliases) do
    [in_predicates(left, right, params, schema, root_aliases)]
  end

  defp predicate_branches_in_expr({:is_nil, _meta, [expr]}, _params, schema, root_aliases) do
    [nil_predicates(expr, schema, root_aliases)]
  end

  defp predicate_branches_in_expr(_expr, _params, _schema, _root_aliases), do: [[]]

  defp merge_predicate_branches(nil, branches), do: branches

  defp merge_predicate_branches(left_branches, right_branches) do
    for left <- left_branches, right <- right_branches do
      left ++ right
    end
  end

  defp concat_predicate_branches(nil, branches), do: branches

  defp concat_predicate_branches(left_branches, right_branches),
    do: left_branches ++ right_branches

  defp equality_predicates(left, right, params, schema, root_aliases) do
    case field_predicate(left, right, :==, params, schema, root_aliases) do
      {:ok, predicate} ->
        [predicate]

      :error ->
        case field_predicate(right, left, :==, params, schema, root_aliases) do
          {:ok, predicate} -> [predicate]
          :error -> []
        end
    end
  end

  defp in_predicates(left, right, params, schema, root_aliases) do
    case direct_root_field(left, root_aliases) do
      {:ok, field} ->
        case comparable_values(schema, field, right, params) do
          {:ok, values} -> [%{field: field, operator: :in, values: values}]
          :error -> []
        end

      :error ->
        []
    end
  end

  defp nil_predicates(expr, schema, root_aliases) do
    with {:ok, field} <- direct_root_field(expr, root_aliases),
         true <- schema_field?(schema, field) do
      [%{field: field, operator: :is_nil, values: [nil]}]
    else
      _other -> []
    end
  end

  defp field_predicate(field_expr, value_expr, operator, params, schema, root_aliases) do
    with {:ok, field} <- direct_root_field(field_expr, root_aliases),
         {:ok, value} <- comparable_value(schema, field, value_expr, params) do
      {:ok, %{field: field, operator: operator, values: [value]}}
    end
  end

  defp comparable_value(schema, field, expr, params) do
    with true <- schema_field?(schema, field),
         {:ok, value} <- value(expr, params) do
      normalize_comparable_value(schema, field, value)
    else
      _other -> :error
    end
  end

  defp comparable_values(schema, field, expr, params) do
    with true <- schema_field?(schema, field),
         {:ok, values} <- values(expr, params) do
      normalize_comparable_values(schema, field, values)
    else
      _other -> :error
    end
  end

  defp schema_field?(schema, field), do: field in schema.__schema__(:fields)

  defp enum_field?(schema, field) do
    schema
    |> schema_type(field)
    |> Ecto.Type.parameterized?(Ecto.Enum)
  end

  defp schema_type(schema, field), do: schema.__schema__(:type, field)

  defp normalize_comparable_value(schema, field, value) do
    cond do
      enum_field?(schema, field) ->
        cast_enum_value(schema, field, value)

      comparable_value_for_type?(schema_type(schema, field), value) ->
        {:ok, value}

      true ->
        :error
    end
  end

  defp cast_enum_value(schema, field, value) do
    case Ecto.Enum.cast_value(schema, field, value) do
      {:ok, enum_value} -> {:ok, enum_value}
      :error -> :error
    end
  end

  defp normalize_comparable_values(_schema, _field, []), do: {:ok, []}

  defp normalize_comparable_values(schema, field, values) do
    values
    |> Enum.reduce_while([], fn value, acc ->
      case normalize_comparable_value(schema, field, value) do
        {:ok, nil} -> {:cont, acc}
        {:ok, comparable_value} -> {:cont, [comparable_value | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      comparable_values -> {:ok, comparable_values |> Enum.uniq() |> Enum.sort()}
    end
  end

  defp comparable_value_for_type?(type, value) when type in [:id, :integer], do: is_integer(value)

  defp comparable_value_for_type?(type, value) when type in [:string, :binary, :binary_id],
    do: is_binary(value)

  defp comparable_value_for_type?(:boolean, value), do: is_boolean(value)
  defp comparable_value_for_type?(_type, _value), do: false

  defp value(%Ecto.Query.Tagged{value: value}, _params), do: {:ok, value}

  defp value({:^, _meta, [index]}, params) when is_integer(index) do
    case Enum.fetch(params, index) do
      {:ok, {value, _type}} -> {:ok, value}
      :error -> :error
    end
  end

  defp value(value, _params)
       when is_atom(value) or is_binary(value) or is_integer(value) do
    {:ok, value}
  end

  defp value(_expr, _params), do: :error

  defp values(%Ecto.Query.Tagged{value: values}, _params) when is_list(values), do: {:ok, values}

  defp values({:^, _meta, [index]} = expr, params) when is_integer(index) do
    case value(expr, params) do
      {:ok, values} when is_list(values) -> {:ok, values}
      _other -> :error
    end
  end

  defp values(values, params) when is_list(values) do
    values
    |> Enum.reduce_while([], fn expr, acc ->
      case value(expr, params) do
        {:ok, value} -> {:cont, [value | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      values -> {:ok, Enum.reverse(values)}
    end
  end

  defp values(_expr, _params), do: :error

  defp direct_root_field({{:., _meta, [source, field]}, _call_meta, []}, root_aliases)
       when is_atom(field) do
    if root_binding?(source, root_aliases) do
      {:ok, field}
    else
      :error
    end
  end

  defp direct_root_field({:field, _meta, [source, field]}, root_aliases) when is_atom(field) do
    if root_binding?(source, root_aliases) do
      {:ok, field}
    else
      :error
    end
  end

  defp direct_root_field(_expr, _root_aliases), do: :error

  defp root_binding?({:&, _meta, [0]}, _root_aliases), do: true

  defp root_binding?({:as, _meta, [alias_name]}, root_aliases) when is_atom(alias_name) do
    MapSet.member?(root_aliases, alias_name)
  end

  defp root_binding?(_expr, _root_aliases), do: false

  defp issues(operation, schema, predicate_branches) do
    branch_issues = Enum.map(predicate_branches, &issues_for_predicates(operation, schema, &1))

    if Enum.any?(branch_issues, &Enum.empty?/1) do
      []
    else
      branch_issues
      |> List.flatten()
      |> Enum.uniq_by(&issue_key/1)
      |> Enum.sort_by(&{&1.meta.field, inspect(&1.meta.predicates)})
    end
  end

  defp issues_for_predicates(operation, schema, predicates) do
    predicates
    |> Enum.group_by(& &1.field)
    |> Enum.flat_map(fn {field, field_predicates} ->
      if conflicting?(field_predicates) do
        [issue(operation, schema, field, field_predicates)]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.meta.field)
  end

  defp issue_key(issue) do
    {
      issue.meta.field,
      Enum.map(issue.meta.predicates, &{&1.operator, &1.values})
    }
  end

  defp conflicting?(predicates) do
    predicates
    |> Enum.map(&MapSet.new(&1.values))
    |> intersection()
    |> Enum.empty?()
  end

  defp intersection([first | rest]), do: Enum.reduce(rest, first, &MapSet.intersection/2)

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
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

  defp predicate_meta(predicate) do
    %{
      operator: predicate.operator,
      values: predicate.values
    }
  end
end
