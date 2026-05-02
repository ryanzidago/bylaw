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

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :mandatory_join_keys
  def name, do: :mandatory_join_keys

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    if disabled?(check_opts) do
      :ok
    else
      keys = fetch_keys!(check_opts)
      match = fetch_match!(check_opts)

      case issues(operation, query, keys, match) do
        [] -> :ok
        [issue] -> {:error, issue}
        issues -> {:error, issues}
      end
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

  defp disabled?(opts), do: Keyword.get(opts, :validate, true) == false

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
    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      binding_index = join_index + 1

      with {:ok, schema} <- explicit_join_schema(join),
           applicable_keys when applicable_keys != [] <- applicable_keys(schema, keys),
           found_keys <- join_keys(join, binding_index),
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
        _ -> []
      end
    end)
  end

  defp issues(_operation, _query, _keys, _match), do: []

  defp explicit_join_schema(%{assoc: assoc}) when not is_nil(assoc), do: :skip

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
    schema_fields = MapSet.new(schema.__schema__(:fields))
    Enum.filter(keys, &MapSet.member?(schema_fields, &1))
  end

  defp join_keys(%{on: %{expr: expr}}, binding_index) do
    expr
    |> keys_in_join_expr(binding_index)
    |> MapSet.new()
  end

  defp join_keys(_join, _binding_index), do: MapSet.new()

  defp keys_in_join_expr({:and, _meta, [left, right]}, binding_index) do
    keys_in_join_expr(left, binding_index) ++ keys_in_join_expr(right, binding_index)
  end

  defp keys_in_join_expr({:==, _meta, [left, right]}, binding_index) do
    case {direct_field(left), direct_field(right)} do
      {{^binding_index, field}, {other_index, field}}
      when is_integer(other_index) and other_index < binding_index ->
        [field]

      {{other_index, field}, {^binding_index, field}}
      when is_integer(other_index) and other_index < binding_index ->
        [field]

      _ ->
        []
    end
  end

  defp keys_in_join_expr(_expr, _binding_index), do: []

  defp direct_field({{:., _meta, [{:&, _source_meta, [binding_index]}, field]}, _call_meta, []})
       when is_integer(binding_index) and is_atom(field) do
    {binding_index, field}
  end

  defp direct_field({:field, _meta, [{:&, _source_meta, [binding_index]}, field]})
       when is_integer(binding_index) and is_atom(field) do
    {binding_index, field}
  end

  defp direct_field(_expr), do: :unknown

  defp missing_keys(keys, found_keys, :any) do
    if Enum.any?(keys, &MapSet.member?(found_keys, &1)), do: [], else: keys
  end

  defp missing_keys(keys, found_keys, :all) do
    Enum.reject(keys, &MapSet.member?(found_keys, &1))
  end

  defp issue(operation, join_index, binding_index, schema, keys, found_keys, missing_keys, match) do
    %Issue{
      check: __MODULE__,
      code: :missing_mandatory_join_key,
      message: message(schema, keys, missing_keys, match),
      meta: %{
        operation: operation,
        join_index: join_index,
        binding_index: binding_index,
        join_schema: schema,
        keys: keys,
        match: match,
        missing_keys: missing_keys,
        found_join_keys: found_keys |> MapSet.to_list() |> Enum.sort()
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
