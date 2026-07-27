defmodule Bylaw.Ecto.Query.Checks.DeterministicOrder do
  @moduledoc """
  Validates that ordered queries include a known unique key for the root source.

  This is useful when callers page through ordered rows or use helpers such as
  `Repo.one/2` with `Ecto.Query.first/2` or `Ecto.Query.last/2`. Ordering by a
  non-unique field such as `:inserted_at` or `:name` leaves rows with the same
  value free to move between executions unless the query also orders by a
  deterministic tie-breaker.

  By default, this check trusts the root Ecto schema primary key. Callers may
  also provide a zero-arity `:unique_keys` resolver that returns verified
  database unique keys by `{database_schema, table}`.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> order_by([post: p], desc: p.inserted_at)
      |> limit(10)

  Why this is bad:

  `inserted_at` is not guaranteed to be unique. Rows with the same timestamp can
  move between executions, which can make paginated queries skip or duplicate
  rows.

  Better:

      from(Post, as: :post)
      |> order_by([post: p], desc: p.inserted_at)
      |> order_by([post: p], asc: p.id)
      |> limit(10)

  Why this is better:

  The root primary key resolves ties in the visible sort key, so every row has a
  stable relative position.

  Better for a composite primary key:

      from(Membership, as: :membership)
      |> order_by([membership: mem], asc: mem.inserted_at)
      |> order_by([membership: mem], asc: mem.organization_id)
      |> order_by([membership: mem], asc: mem.sequence)

  ## Notes

  Without a `:unique_keys` resolver, this check only trusts the root Ecto schema
  primary key. It cannot independently verify arbitrary database unique indexes
  or schema-less query sources.

  The check infers root schema primary keys with Ecto schema reflection. A
  resolver can additionally prove database-backed keys for schema and
  schema-less table sources. Unsupported query sources return an issue unless
  validation is explicitly disabled.

  ## Options

    * `:validate` - explicit `false` disables this check. It can be used in the
      repo-wide check list or in call-site overrides passed to
      `Bylaw.Ecto.Query.validate/4`.
    * `:unique_keys` - optional zero-arity function returning a map from
      `{database_schema, table}` to lists of unique database column sets:

          fn ->
            %{
              {"public", "posts"} => [
                ["id"],
                ["slug"],
                ["organisation_id", "sequence"]
              ]
            }
          end

      Database schemas may be `nil` for unqualified visible table entries.
      Resolver failures are not suppressed. Invalid return values raise
      `ArgumentError`.

  Run globally with defaults:

      Bylaw.Ecto.Query.Checks.DeterministicOrder

  Run only for matching rule scopes:

      {Bylaw.Ecto.Query.Checks.DeterministicOrder,
       rules: [
         [where: [ecto_schemas: [Post]]],
         [where: [tables: ["posts"]]]
       ]}

  This check has no check-specific rule options. `:unique_keys` configures the
  whole check and cannot be set inside individual rules.

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.Ecto.Query`.
  See `Bylaw.Ecto.Query` for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue
  alias Bylaw.Ecto.Query.RuleOptions

  @typedoc false
  @type field_set :: list(atom())
  @typedoc """
  Verified unique database columns for one table.
  """
  @type unique_key :: nonempty_list(String.t())
  @typedoc """
  Verified unique database columns keyed by database schema and table.
  """
  @type unique_key_catalogue :: %{
          optional({String.t() | nil, String.t()}) => list(unique_key())
        }
  @typedoc """
  Function used to resolve verified database unique keys.
  """
  @type unique_keys_resolver :: (-> unique_key_catalogue())
  @typedoc false
  @type check_opts ::
          list({:validate, boolean()} | {:unique_keys, unique_keys_resolver()})
  @typedoc false
  @type opts :: check_opts()

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate, :rules, :unique_keys])
    scope_opts = Keyword.delete(check_opts, :unique_keys)

    if CheckOptions.enabled?(check_opts) and
         RuleOptions.scoped?(scope_opts, :deterministic_order, operation, query) and
         ordered?(query) do
      validate_ordered_query(operation, query, check_opts)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_ordered_query(operation, query, opts) do
    fields = order_fields(query)
    primary_key = primary_key(query)

    if deterministic?(fields, primary_key) do
      :ok
    else
      validate_resolved_unique_keys(operation, query, fields, primary_key, opts)
    end
  end

  defp validate_resolved_unique_keys(operation, query, fields, primary_key, opts) do
    case Keyword.fetch(opts, :unique_keys) do
      {:ok, resolver} ->
        resolver = unique_keys_resolver!(resolver)
        unique_keys = unique_keys(query, resolver.())

        if deterministic_database_fields?(query, fields, unique_keys) do
          :ok
        else
          {:error, [issue(operation, fields, primary_key, unique_keys)]}
        end

      :error ->
        {:error, [issue(operation, fields, primary_key)]}
    end
  end

  defp primary_key(query) do
    case Introspection.root_schema(query) do
      {:ok, schema} ->
        schema.__schema__(:primary_key)

      :unknown ->
        []
    end
  end

  defp ordered?(%{order_bys: order_bys}) when is_list(order_bys), do: not Enum.empty?(order_bys)
  defp ordered?(_query), do: false

  @spec order_fields(term()) :: field_set()
  defp order_fields(query) when is_map(query) do
    root_aliases = Introspection.root_aliases(query)

    query
    |> Map.get(:order_bys, [])
    |> Enum.flat_map(fn order_by ->
      order_by
      |> Map.get(:expr, [])
      |> fields_in_order_expr(root_aliases)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp order_fields(_query), do: []

  defp fields_in_order_expr(exprs, root_aliases) when is_list(exprs) do
    Enum.flat_map(exprs, fn
      {_direction, expr} -> Introspection.root_fields(expr, root_aliases)
      expr -> Introspection.root_fields(expr, root_aliases)
    end)
  end

  defp fields_in_order_expr(_expr, _root_aliases), do: []

  @spec deterministic?(field_set(), field_set()) :: boolean()
  defp deterministic?(_fields, []), do: false

  defp deterministic?(fields, primary_key) do
    Enum.all?(primary_key, &Enum.member?(fields, &1))
  end

  defp deterministic_database_fields?(_query, _fields, []), do: false

  defp deterministic_database_fields?(query, fields, unique_keys) do
    database_fields =
      query
      |> database_order_fields(fields)
      |> MapSet.new()

    Enum.any?(unique_keys, fn unique_key ->
      unique_key
      |> MapSet.new()
      |> MapSet.subset?(database_fields)
    end)
  end

  defp database_order_fields(query, fields) do
    case Introspection.root_schema(query) do
      {:ok, schema} ->
        Enum.flat_map(fields, fn field ->
          if Introspection.schema_field?(schema, field) do
            [database_field(schema.__schema__(:field_source, field))]
          else
            []
          end
        end)

      :unknown ->
        Enum.map(fields, &Atom.to_string/1)
    end
  end

  defp database_field(field) when is_atom(field), do: Atom.to_string(field)
  defp database_field(field) when is_binary(field), do: field

  defp unique_keys(query, catalogue) do
    catalogue = unique_key_catalogue!(catalogue)
    source = {Introspection.root_prefix(query), Introspection.root_table(query)}

    Map.get(catalogue, source, [])
  end

  defp unique_keys_resolver!(resolver) when is_function(resolver, 0), do: resolver

  defp unique_keys_resolver!(resolver) do
    raise ArgumentError,
          "expected :unique_keys to be a zero-arity function, got: #{inspect(resolver)}"
  end

  defp unique_key_catalogue!(catalogue) when is_map(catalogue) do
    Enum.each(catalogue, fn {source, unique_keys} ->
      unique_key_source!(source)
      unique_keys!(unique_keys, source)
    end)

    catalogue
  end

  defp unique_key_catalogue!(catalogue) do
    raise ArgumentError,
          "expected :unique_keys resolver to return a map, got: #{inspect(catalogue)}"
  end

  defp unique_key_source!({database_schema, table})
       when (is_nil(database_schema) or is_binary(database_schema)) and is_binary(table) do
    if (is_binary(database_schema) and byte_size(database_schema) == 0) or byte_size(table) == 0 do
      raise_unique_key_source_error!({database_schema, table})
    end
  end

  defp unique_key_source!(source), do: raise_unique_key_source_error!(source)

  defp unique_keys!(unique_keys, source) when is_list(unique_keys) do
    Enum.each(unique_keys, &unique_key!(&1, source))
  end

  defp unique_keys!(unique_keys, source) do
    raise ArgumentError,
          "expected unique keys for #{inspect(source)} to be a list, got: #{inspect(unique_keys)}"
  end

  defp unique_key!(unique_key, source) when is_list(unique_key) do
    if Enum.empty?(unique_key) or
         Enum.any?(unique_key, &(not is_binary(&1) or byte_size(&1) == 0)) do
      raise_unique_key_error!(unique_key, source)
    end
  end

  defp unique_key!(unique_key, source), do: raise_unique_key_error!(unique_key, source)

  defp raise_unique_key_source_error!(source) do
    raise ArgumentError,
          "expected :unique_keys map keys to be {database_schema, table} string tuples, got: #{inspect(source)}"
  end

  defp raise_unique_key_error!(unique_key, source) do
    raise ArgumentError,
          "expected unique keys for #{inspect(source)} to contain non-empty lists of non-empty strings, got: #{inspect(unique_key)}"
  end

  @spec issue(Bylaw.Ecto.Query.Check.operation(), field_set(), field_set()) :: Issue.t()
  defp issue(operation, fields, primary_key) do
    %Issue{
      check: __MODULE__,
      message: message(primary_key),
      meta: %{
        operation: operation,
        primary_key: primary_key,
        found_order_keys: fields
      }
    }
  end

  defp issue(operation, fields, primary_key, unique_keys) do
    %Issue{
      check: __MODULE__,
      message: message(primary_key, unique_keys),
      meta: %{
        operation: operation,
        primary_key: primary_key,
        found_order_keys: fields,
        unique_keys: unique_keys
      }
    }
  end

  defp message([]) do
    "expected ordered query to include the root primary key, but no root primary key is known"
  end

  defp message(primary_key) do
    "expected ordered query to include the root primary key: #{format_keys(primary_key)}"
  end

  defp message([], []) do
    "expected ordered query to include a verified root unique key, but none are known"
  end

  defp message(primary_key, []) do
    "expected ordered query to include the root primary key: #{format_keys(primary_key)}"
  end

  defp message(primary_key, unique_keys) do
    primary_keys =
      if Enum.empty?(primary_key) do
        []
      else
        [Enum.map(primary_key, &Atom.to_string/1)]
      end

    "expected ordered query to include a verified root unique key: #{format_unique_keys(primary_keys ++ unique_keys)}"
  end

  defp format_keys(keys), do: Enum.map_join(keys, ", ", &inspect/1)

  defp format_unique_keys(unique_keys) do
    Enum.map_join(unique_keys, " or ", fn unique_key ->
      formatted_key = Enum.map_join(unique_key, ", ", &inspect/1)
      "(#{formatted_key})"
    end)
  end
end
