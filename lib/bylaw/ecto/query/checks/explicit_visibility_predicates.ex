defmodule Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates do
  @moduledoc """
  Validates that configured visibility-sensitive fields are explicitly constrained.

  This check is about query explicitness, not visibility correctness. Callers
  configure the schema fields that affect record visibility or lifecycle in
  their application, such as `:deleted_at`, `:archived_at`, `:hidden_at`,
  `:status`, `:state`, or `:published_at`. Bylaw only verifies that queries
  against configured schemas mention those fields in supported root `where`
  predicates.

      @bylaw [
        explicit_visibility_predicates: [
          schemas: [
            {Post, fields: [:deleted_at, :archived_at, :status]},
            {Comment, fields: [:deleted_at]}
          ]
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates.validate(
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

      Repo.all(query, bylaw: [explicit_visibility_predicates: [validate: false]])

  Supported options:

      [
        explicit_visibility_predicates: [
          validate: true,
          schemas: [
            {Post, fields: [:deleted_at, :status]}
          ]
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:schemas` - list of `{schema, fields: fields}` tuples. Defaults to `[]`.

  The check is static. It accepts configured root fields when they appear
  directly in `where` expressions, including `is_nil(field)`, `not is_nil(field)`,
  bare field predicates, comparisons against values or parameters, and `in`
  predicates whose right side has no field references. Field-to-field
  comparisons are not treated as explicit constraints. It cannot prove visibility
  fields hidden inside raw SQL fragments or subqueries.

  When the root query schema is not configured, the check returns `:ok`.
  Configured fields that do not exist on the root schema are ignored. If no
  applicable configured fields remain, the check returns `:ok`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]

  @type schema_config :: {module(), list({:fields, list(atom())})}
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:schemas, list(schema_config())}
          )
  @type opts :: list({:explicit_visibility_predicates, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :explicit_visibility_predicates
  def name, do: :explicit_visibility_predicates

  @doc """
  Validates explicit visibility-sensitive root `where` predicates.

  The operation is kept as issue metadata. This check applies the same query
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      check_opts = check_opts!(opts)

      if disabled?(check_opts) do
        :ok
      else
        validate_enabled(operation, query, check_opts)
      end
    else
      raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp check_opts!(opts) do
    opts
    |> Keyword.get(name(), [])
    |> normalize_check_opts!()
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

  defp validate_check_opt!({:schemas, _value}), do: :ok
  defp validate_check_opt!({:validate, _value}), do: :ok

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp disabled?(opts), do: Keyword.get(opts, :validate, true) == false

  defp validate_enabled(operation, query, check_opts) do
    schema_configs = fetch_schema_configs!(check_opts)

    with {:ok, schema} <- root_schema(query),
         {:ok, configured_fields} <- configured_fields(schema_configs, schema),
         applicable_fields = applicable_fields(schema, configured_fields),
         false <- Enum.empty?(applicable_fields) do
      validate_applicable_fields(operation, query, schema, configured_fields, applicable_fields)
    else
      _not_applicable -> :ok
    end
  end

  defp validate_applicable_fields(operation, query, schema, configured_fields, applicable_fields) do
    field_branches = where_field_branches(query)
    fields = guaranteed_fields(field_branches)
    missing = missing_fields(applicable_fields, field_branches)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, issue(operation, schema, configured_fields, applicable_fields, fields, missing)}
    end
  end

  defp fetch_schema_configs!(opts) do
    opts
    |> Keyword.get(:schemas, [])
    |> normalize_schema_configs!()
  end

  defp normalize_schema_configs!(schemas) when is_list(schemas) do
    Enum.map(schemas, &normalize_schema_config!/1)
  end

  defp normalize_schema_configs!(schemas) do
    raise ArgumentError,
          "expected :schemas to be a list of {schema, fields: fields} tuples, got: #{inspect(schemas)}"
  end

  defp normalize_schema_config!({schema, schema_opts})
       when is_atom(schema) and is_list(schema_opts) do
    cond do
      not function_exported?(schema, :__schema__, 1) ->
        raise ArgumentError,
              "expected configured schema to be an Ecto schema, got: #{inspect(schema)}"

      not Keyword.keyword?(schema_opts) ->
        raise ArgumentError,
              "expected schema options for #{inspect(schema)} to be a keyword list, got: #{inspect(schema_opts)}"

      true ->
        Enum.each(schema_opts, &validate_schema_opt!(schema, &1))
        {schema, fields: fetch_fields!(schema, schema_opts)}
    end
  end

  defp normalize_schema_config!(schema_config) do
    raise ArgumentError,
          "expected :schemas to contain {schema, fields: fields} tuples, got: #{inspect(schema_config)}"
  end

  defp validate_schema_opt!(_schema, {:fields, _value}), do: :ok

  defp validate_schema_opt!(schema, {key, _value}) do
    raise ArgumentError, "unknown option for schema #{inspect(schema)}: #{inspect(key)}"
  end

  defp fetch_fields!(schema, opts) do
    case Keyword.fetch(opts, :fields) do
      {:ok, fields} ->
        normalize_fields!(schema, fields)

      :error ->
        raise ArgumentError, "missing required :fields option for schema #{inspect(schema)}"
    end
  end

  defp normalize_fields!(_schema, []) do
    raise ArgumentError,
          "expected :fields to be a non-empty list of atoms, got: []"
  end

  defp normalize_fields!(_schema, fields) when is_list(fields) do
    fields
    |> Enum.map(&normalize_field!/1)
    |> Enum.uniq()
  end

  defp normalize_fields!(_schema, fields) do
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

  defp configured_fields(schema_configs, schema) do
    case Enum.find(schema_configs, fn {configured_schema, _opts} ->
           configured_schema == schema
         end) do
      {^schema, fields: fields} -> {:ok, fields}
      nil -> :unknown
    end
  end

  defp applicable_fields(schema, fields) do
    schema_field_names = schema.__schema__(:fields)
    schema_fields = MapSet.new(schema_field_names)

    Enum.filter(fields, &MapSet.member?(schema_fields, &1))
  end

  defp where_field_branches(query) when is_map(query) do
    aliases = query_aliases(query)

    branches =
      query
      |> Map.get(:wheres, [])
      |> Enum.reduce(nil, fn where, branches ->
        expr_branches = field_branches_in_expr(Map.get(where, :expr), aliases)

        case Map.get(where, :op, :and) do
          :or -> concat_branches(branches, expr_branches)
          _op -> merge_branch_fields(branches, expr_branches)
        end
      end)

    case branches do
      nil -> [MapSet.new()]
      branches -> branches
    end
  end

  defp where_field_branches(_query), do: [MapSet.new()]

  defp query_aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  defp query_aliases(_query), do: %{}

  defp field_branches_in_expr({:and, _meta, [left, right]}, aliases) do
    merge_branch_fields(
      field_branches_in_expr(left, aliases),
      field_branches_in_expr(right, aliases)
    )
  end

  defp field_branches_in_expr({:or, _meta, [left, right]}, aliases) do
    field_branches_in_expr(left, aliases) ++ field_branches_in_expr(right, aliases)
  end

  defp field_branches_in_expr({:not, _meta, [{:is_nil, _is_nil_meta, [expr]}]}, aliases) do
    fields = direct_root_fields(expr, aliases)
    [MapSet.new(fields)]
  end

  defp field_branches_in_expr({:not, _meta, [{op, _op_meta, [_left, _right]} = expr]}, aliases)
       when op in @comparison_ops or op == :in do
    field_branches_in_expr(expr, aliases)
  end

  defp field_branches_in_expr({:not, _meta, [expr]}, aliases) do
    fields = direct_root_fields(expr, aliases)
    [MapSet.new(fields)]
  end

  defp field_branches_in_expr({:is_nil, _meta, [expr]}, aliases) do
    fields = direct_root_fields(expr, aliases)
    [MapSet.new(fields)]
  end

  defp field_branches_in_expr({op, _meta, [left, right]}, aliases) when op in @comparison_ops do
    fields = comparison_root_fields(left, right, aliases)
    [MapSet.new(fields)]
  end

  defp field_branches_in_expr({:in, _meta, [left, right]}, aliases) do
    if field_reference?(right) do
      [MapSet.new()]
    else
      fields = direct_root_fields(left, aliases)
      [MapSet.new(fields)]
    end
  end

  defp field_branches_in_expr(expr, aliases) do
    fields = direct_root_fields(expr, aliases)
    [MapSet.new(fields)]
  end

  defp merge_branch_fields(nil, branches), do: branches

  defp merge_branch_fields(left_branches, right_branches) do
    for left <- left_branches, right <- right_branches do
      MapSet.union(left, right)
    end
  end

  defp concat_branches(nil, branches), do: branches
  defp concat_branches(left_branches, right_branches), do: left_branches ++ right_branches

  defp guaranteed_fields([first | rest]) do
    Enum.reduce(rest, first, &MapSet.intersection/2)
  end

  defp guaranteed_fields([]), do: MapSet.new()

  defp comparison_root_fields(left, right, aliases) do
    cond do
      field_reference?(left) and field_reference?(right) ->
        []

      field_reference?(left) ->
        direct_root_fields(left, aliases)

      field_reference?(right) ->
        direct_root_fields(right, aliases)

      true ->
        []
    end
  end

  defp direct_root_fields({{:., _meta, [source, field]}, _call_meta, []}, aliases)
       when is_atom(field) do
    if root_binding?(source, aliases) do
      [field]
    else
      []
    end
  end

  defp direct_root_fields({:field, _meta, [source, field]}, aliases) when is_atom(field) do
    if root_binding?(source, aliases) do
      [field]
    else
      []
    end
  end

  defp direct_root_fields(_expr, _aliases), do: []

  defp field_reference?({{:., _meta, [_source, field]}, _call_meta, []}) when is_atom(field),
    do: true

  defp field_reference?({:field, _meta, [_source, field]}) when is_atom(field), do: true

  defp field_reference?(expr) when is_tuple(expr) do
    expr
    |> Tuple.to_list()
    |> field_reference?()
  end

  defp field_reference?(expr) when is_list(expr), do: Enum.any?(expr, &field_reference?/1)
  defp field_reference?(_expr), do: false

  defp root_binding?({:&, _meta, [0]}, _aliases), do: true
  defp root_binding?({:as, _meta, [name]}, aliases) when is_atom(name), do: aliases[name] == 0
  defp root_binding?(_expr, _aliases), do: false

  defp missing_fields(fields, field_branches) do
    Enum.reject(fields, fn field ->
      Enum.all?(field_branches, &MapSet.member?(&1, field))
    end)
  end

  defp issue(operation, schema, configured_fields, applicable_fields, found_fields, missing) do
    %Issue{
      check: __MODULE__,
      message: message(missing),
      meta: %{
        operation: operation,
        root_schema: schema,
        configured_fields: configured_fields,
        applicable_fields: applicable_fields,
        missing_fields: missing,
        found_visibility_fields: found_visibility_fields(found_fields, applicable_fields)
      }
    }
  end

  defp found_visibility_fields(found_fields, applicable_fields) do
    applicable_fields
    |> MapSet.new()
    |> MapSet.intersection(found_fields)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp message(missing) do
    "expected query to explicitly constrain visibility-sensitive fields: #{format_fields(missing)}"
  end

  defp format_fields(fields) do
    Enum.map_join(fields, ", ", &inspect/1)
  end
end
