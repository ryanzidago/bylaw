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

    if disabled?(check_opts) do
      :ok
    else
      keys = fetch_keys!(check_opts)
      applicable_keys = applicable_keys(query, keys)

      if Enum.empty?(applicable_keys) do
        :ok
      else
        match = fetch_match!(check_opts)
        fields = where_fields(query)
        missing = missing_keys(applicable_keys, fields, match)

        if Enum.empty?(missing) do
          :ok
        else
          {:error, issue(operation, applicable_keys, fields, missing, match)}
        end
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
      {:ok, keys} when is_list(keys) ->
        if Enum.empty?(keys) do
          raise ArgumentError,
                "expected :keys to be a non-empty list of atoms, got: #{inspect(keys)}"
        else
          Enum.map(keys, fn
            key when is_atom(key) ->
              key

            key ->
              raise ArgumentError,
                    "expected :keys to contain only atoms, got: #{inspect(key)}"
          end)
        end

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

  defp where_fields(query) when is_map(query) do
    query
    |> Map.get(:wheres, [])
    |> Enum.flat_map(fn where -> where |> Map.get(:expr) |> fields_in_expr() end)
    |> MapSet.new()
  end

  defp where_fields(_query), do: MapSet.new()

  defp fields_in_expr({:and, _meta, [left, right]}) do
    fields_in_expr(left) ++ fields_in_expr(right)
  end

  defp fields_in_expr({:==, _meta, [left, right]}) do
    direct_root_fields(left) ++ direct_root_fields(right)
  end

  defp fields_in_expr({:in, _meta, [left, _right]}) do
    direct_root_fields(left)
  end

  defp fields_in_expr(_expr), do: []

  defp direct_root_fields({{:., _meta, [source, field]}, _call_meta, []}) when is_atom(field) do
    if root_binding?(source) do
      [field]
    else
      []
    end
  end

  defp direct_root_fields({:field, _meta, [source, field]}) when is_atom(field) do
    if root_binding?(source) do
      [field]
    else
      []
    end
  end

  defp direct_root_fields(_expr), do: []

  defp root_binding?({:&, _meta, [0]}), do: true
  defp root_binding?(_expr), do: false

  defp missing_keys(keys, fields, :any) do
    if Enum.any?(keys, &MapSet.member?(fields, &1)), do: [], else: keys
  end

  defp missing_keys(keys, fields, :all) do
    Enum.reject(keys, &MapSet.member?(fields, &1))
  end

  defp issue(operation, keys, fields, missing, match) do
    %Issue{
      check: __MODULE__,
      code: :missing_mandatory_where_key,
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
    keys
    |> Enum.map(&inspect/1)
    |> Enum.join(", ")
  end
end
