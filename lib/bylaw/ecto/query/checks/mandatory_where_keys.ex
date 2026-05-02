defmodule Bylaw.Ecto.Query.Checks.MandatoryWhereKeys do
  @moduledoc """
  Validates that a query has a root `where` predicate referencing configured keys.

  This is useful for tenant boundaries where every query should include a
  predicate for fields such as `:organisation_id` or `:user_id`.

      @bylaw [
        mandatory_where_keys: [
          keys: [:organisation_id, :user_id]
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.MandatoryWhereKeys.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [mandatory_where_keys: [validate: false]])

  Supported options:

      [
        mandatory_where_keys: [
          validate: true,
          keys: [:organisation_id, :user_id],
          match: :any
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:keys` - required non-empty list of field names when the check runs.
    * `:match` - `:any` or `:all`. Defaults to `:any`.

  The check is static. It accepts configured root fields directly in `==` and `in`
  predicates inside `where` expressions, but it cannot prove fields hidden
  inside raw SQL fragments.

  When the root query uses an Ecto schema, the configured keys are first narrowed
  to fields that exist on that schema. If none of the configured keys exist, the
  check is not applicable and returns `:ok`. Schema-less sources are still
  validated because there is no schema reflection signal.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type match :: :any | :all
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:keys, list(atom())}
            | {:match, match()}
          )
  @type opts :: list({:mandatory_where_keys, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :mandatory_where_keys
  def name, do: :mandatory_where_keys

  @doc """
  Validates mandatory root `where` predicates for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same query
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

  defp validate_check_opt!({:keys, _value}), do: :ok
  defp validate_check_opt!({:match, _value}), do: :ok
  defp validate_check_opt!({:validate, _value}), do: :ok

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp validate_enabled(operation, query, check_opts) do
    keys = fetch_keys!(check_opts)

    case applicable_keys(query, keys) do
      [] -> :ok
      applicable_keys -> validate_applicable_keys(operation, query, check_opts, applicable_keys)
    end
  end

  defp validate_applicable_keys(operation, query, check_opts, applicable_keys) do
    match = fetch_match!(check_opts)
    field_branches = where_field_branches(query)
    fields = guaranteed_fields(field_branches)
    missing = missing_keys(applicable_keys, field_branches, match)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, issue(operation, applicable_keys, fields, missing, match)}
    end
  end

  defp fetch_keys!(opts) do
    case Keyword.fetch(opts, :keys) do
      {:ok, keys} ->
        normalize_keys!(keys)

      :error ->
        raise ArgumentError, "missing required :keys option"
    end
  end

  defp normalize_keys!([]) do
    raise ArgumentError,
          "expected :keys to be a non-empty list of atoms, got: []"
  end

  defp normalize_keys!(keys) when is_list(keys), do: Enum.map(keys, &normalize_key!/1)

  defp normalize_keys!(keys) do
    raise ArgumentError,
          "expected :keys to be a non-empty list of atoms, got: #{inspect(keys)}"
  end

  defp normalize_key!(key) when is_atom(key), do: key

  defp normalize_key!(key) do
    raise ArgumentError,
          "expected :keys to contain only atoms, got: #{inspect(key)}"
  end

  defp fetch_match!(opts) do
    case Keyword.get(opts, :match, :any) do
      match when match in [:any, :all] ->
        match

      match ->
        raise ArgumentError, "expected :match to be :any or :all, got: #{inspect(match)}"
    end
  end

  defp applicable_keys(query, keys) do
    case root_schema(query) do
      {:ok, schema} ->
        schema_fields = MapSet.new(schema.__schema__(:fields))
        Enum.filter(keys, &MapSet.member?(schema_fields, &1))

      :unknown ->
        keys
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

  defp where_field_branches(query) when is_map(query) do
    aliases = query_aliases(query)

    query
    |> Map.get(:wheres, [])
    |> Enum.reduce(nil, fn where, branches ->
      expr_branches = field_branches_in_expr(Map.get(where, :expr), aliases)

      case Map.get(where, :op, :and) do
        :or -> concat_branches(branches, expr_branches)
        _op -> merge_branch_fields(branches, expr_branches)
      end
    end)
    |> case do
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

  defp field_branches_in_expr({:==, _meta, [left, right]}, aliases) do
    [MapSet.new(equality_root_fields(left, right, aliases))]
  end

  defp field_branches_in_expr({:in, _meta, [left, right]}, aliases) do
    if field_reference?(right) do
      [MapSet.new()]
    else
      [MapSet.new(direct_root_fields(left, aliases))]
    end
  end

  defp field_branches_in_expr(_expr, _aliases), do: [MapSet.new()]

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

  defp equality_root_fields(left, right, aliases) do
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

  defp missing_keys(keys, field_branches, :any) do
    if Enum.all?(field_branches, &branch_has_any_key?(&1, keys)), do: [], else: keys
  end

  defp missing_keys(keys, field_branches, :all) do
    Enum.reject(keys, fn key ->
      Enum.all?(field_branches, &MapSet.member?(&1, key))
    end)
  end

  defp branch_has_any_key?(fields, keys), do: Enum.any?(keys, &MapSet.member?(fields, &1))

  defp issue(operation, keys, fields, missing, match) do
    %Issue{
      check: __MODULE__,
      message: message(keys, missing, match),
      meta: %{
        operation: operation,
        keys: keys,
        match: match,
        missing_keys: missing,
        found_where_keys: fields |> MapSet.to_list() |> Enum.sort()
      }
    }
  end

  defp message(keys, _missing, :any) do
    "expected query to filter by at least one of: #{format_keys(keys)}"
  end

  defp message(_keys, missing, :all) do
    "expected query to filter by all mandatory keys; missing: #{format_keys(missing)}"
  end

  defp format_keys(keys) do
    Enum.map_join(keys, ", ", &inspect/1)
  end
end
