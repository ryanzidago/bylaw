defmodule Bylaw.Ecto.Query.Checks.MandatoryJoinKeys do
  @moduledoc """
  Validates that explicit schema joins preserve configured mandatory keys.

  This check is intentionally narrow. It handles direct schema joins such as:

      from post in Post,
        join: comment in Comment,
        on:
          comment.post_id == post.id and
            comment.organisation_id == post.organisation_id

  Association joins, subqueries, fragments, and schema-less joins are not
  validated by this check.

  Like Bylaw's other Ecto query checks, this reads Ecto query structs directly.
  Ecto treats those structs as opaque, so this check intentionally supports a
  small, tested subset of Ecto's query AST.

  For repo-wide enforcement, call this check from Ecto's
  `c:Ecto.Repo.prepare_query/3` callback:

      @bylaw [
        mandatory_join_keys: [
          keys: [:organisation_id],
          match: :all
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.MandatoryJoinKeys.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue_or_issues} -> raise inspect(issue_or_issues)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [mandatory_join_keys: [validate: false]])

  Supported options:

      [
        mandatory_join_keys: [
          keys: [:organisation_id],
          match: :any
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:keys` - required non-empty list of field names when the check runs.
    * `:match` - `:any` or `:all`. Defaults to `:any`.

  When a join schema does not contain any configured keys, that join is not
  applicable and the check returns no issue for it. For applicable joins, the
  check accepts direct equality predicates between the joined binding and
  another query binding in the join `on` expression.
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
  @type opts :: list({:mandatory_join_keys, check_opts()})
  @type field_set :: list(atom())

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :mandatory_join_keys
  def name, do: :mandatory_join_keys

  @doc """
  Validates mandatory join-key predicates for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same explicit
  join validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    if enabled?(check_opts) do
      keys = fetch_keys!(check_opts)
      match = fetch_match!(check_opts)

      case issues(operation, query, keys, match) do
        [] -> :ok
        [issue] -> {:error, issue}
        issues -> {:error, issues}
      end
    else
      :ok
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

  defp normalize_check_opts!(opts) when is_list(opts), do: opts

  defp normalize_check_opts!(opts) do
    raise ArgumentError,
          "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp fetch_keys!(opts) do
    case Keyword.fetch(opts, :keys) do
      {:ok, []} ->
        raise ArgumentError,
              "expected :keys to be a non-empty list of atoms, got: []"

      {:ok, keys} when is_list(keys) ->
        Enum.map(keys, &validate_key!/1)

      {:ok, keys} ->
        raise ArgumentError,
              "expected :keys to be a non-empty list of atoms, got: #{inspect(keys)}"

      :error ->
        raise ArgumentError, "missing required :keys option"
    end
  end

  defp fetch_match!(opts) do
    case Keyword.get(opts, :match, :any) do
      match when match in [:any, :all] ->
        match

      match ->
        raise ArgumentError, "expected :match to be :any or :all, got: #{inspect(match)}"
    end
  end

  defp validate_key!(key) when is_atom(key), do: key

  defp validate_key!(key) do
    raise ArgumentError,
          "expected :keys to contain only atoms, got: #{inspect(key)}"
  end

  defp issues(operation, query, keys, match) when is_map(query) do
    aliases = query_aliases(query)

    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      binding_index = join_index + 1

      with {:ok, schema} <- explicit_join_schema(join),
           applicable_keys when applicable_keys != [] <- applicable_keys(schema, keys),
           found_keys <- join_keys(join, binding_index, aliases),
           missing_keys <- missing_keys(applicable_keys, found_keys, match),
           false <- Enum.empty?(missing_keys) do
        [
          issue(
            operation,
            join_index,
            binding_index,
            schema,
            applicable_keys,
            found_keys,
            missing_keys,
            match
          )
        ]
      else
        _other -> []
      end
    end)
  end

  defp issues(_operation, _query, _keys, _match), do: []

  defp query_aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  defp query_aliases(_query), do: %{}

  defp explicit_join_schema(%{assoc: assoc}) when assoc != nil, do: :skip

  defp explicit_join_schema(%{source: {_source, schema}})
       when is_atom(schema) and not is_nil(schema) do
    if function_exported?(schema, :__schema__, 1) do
      {:ok, schema}
    else
      :skip
    end
  end

  defp explicit_join_schema(_join), do: :skip

  defp applicable_keys(schema, keys) do
    fields = schema.__schema__(:fields)
    schema_fields = MapSet.new(fields)

    Enum.filter(keys, &MapSet.member?(schema_fields, &1))
  end

  @spec join_keys(term(), pos_integer(), map()) :: field_set()
  defp join_keys(%{on: %{expr: expr}}, binding_index, aliases) do
    expr
    |> keys_in_join_expr(binding_index, aliases)
    |> Enum.uniq()
  end

  defp join_keys(_join, _binding_index, _aliases), do: []

  defp keys_in_join_expr({:and, _meta, [left, right]}, binding_index, aliases) do
    keys_in_join_expr(left, binding_index, aliases) ++
      keys_in_join_expr(right, binding_index, aliases)
  end

  defp keys_in_join_expr({:==, _meta, [left, right]}, binding_index, aliases) do
    case {direct_field(left, aliases), direct_field(right, aliases)} do
      {{^binding_index, field}, {other_index, field}}
      when is_integer(other_index) and other_index < binding_index ->
        [field]

      {{other_index, field}, {^binding_index, field}}
      when is_integer(other_index) and other_index < binding_index ->
        [field]

      _other ->
        []
    end
  end

  defp keys_in_join_expr(_expr, _binding_index, _aliases), do: []

  defp direct_field({{:., _meta, [source, field]}, _call_meta, []}, aliases)
       when is_atom(field) do
    direct_field(source, field, aliases)
  end

  defp direct_field({:field, _meta, [source, field]}, aliases) when is_atom(field) do
    direct_field(source, field, aliases)
  end

  defp direct_field(_expr, _aliases), do: :unknown

  defp direct_field(source, field, aliases) do
    case source_binding_index(source, aliases) do
      binding_index when is_integer(binding_index) -> {binding_index, field}
      :unknown -> :unknown
    end
  end

  defp source_binding_index({:&, _meta, [binding_index]}, _aliases)
       when is_integer(binding_index) do
    binding_index
  end

  defp source_binding_index({:as, _meta, [name]}, aliases) when is_atom(name) do
    Map.get(aliases, name, :unknown)
  end

  defp source_binding_index(_source, _aliases), do: :unknown

  @spec missing_keys(list(atom()), field_set(), match()) :: list(atom())
  defp missing_keys(keys, found_keys, :any) do
    if Enum.any?(keys, &Enum.member?(found_keys, &1)), do: [], else: keys
  end

  defp missing_keys(keys, found_keys, :all) do
    Enum.reject(keys, &Enum.member?(found_keys, &1))
  end

  @spec issue(
          Bylaw.Ecto.Query.Check.operation(),
          non_neg_integer(),
          pos_integer(),
          module(),
          list(atom()),
          field_set(),
          list(atom()),
          match()
        ) :: Issue.t()
  defp issue(operation, join_index, binding_index, schema, keys, found_keys, missing_keys, match) do
    %Issue{
      check: __MODULE__,
      message: message(schema, keys, missing_keys, match),
      meta: %{
        operation: operation,
        join_index: join_index,
        binding_index: binding_index,
        join_schema: schema,
        keys: keys,
        match: match,
        missing_keys: missing_keys,
        found_join_keys: Enum.sort(found_keys)
      }
    }
  end

  defp message(schema, keys, _missing_keys, :any) do
    "expected explicit join to #{inspect(schema)} to match at least one mandatory key with an earlier binding: #{format_keys(keys)}"
  end

  defp message(schema, _keys, missing_keys, :all) do
    "expected explicit join to #{inspect(schema)} to match all mandatory keys with an earlier binding; missing: #{format_keys(missing_keys)}"
  end

  defp format_keys(keys), do: Enum.map_join(keys, ", ", &inspect/1)
end
