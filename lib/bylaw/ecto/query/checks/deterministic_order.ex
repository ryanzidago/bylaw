defmodule Bylaw.Ecto.Query.Checks.DeterministicOrder do
  @moduledoc """
  Validates that ordered queries include the root schema primary key.

  This is useful when callers page through ordered rows or use helpers such as
  `Repo.one/2` with `Ecto.Query.first/2` or `Ecto.Query.last/2`. Ordering by a
  non-unique field such as `:inserted_at` or `:name` leaves rows with the same
  value free to move between executions unless the query also orders by a
  deterministic tie-breaker.

  For now, this check only trusts the root Ecto schema primary key. Ecto schemas
  do not expose arbitrary database unique indexes, and this check should not ask
  callers to manually assert uniqueness that Bylaw cannot verify. If a query is
  intentionally ordered by another unique database key, use the explicit escape
  hatch until a DB-aware check can verify those constraints directly.

      @bylaw [
        deterministic_order: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.DeterministicOrder.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [deterministic_order: [validate: false]])

  Supported options:

      [
        deterministic_order: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check is static. It infers root schema primary keys with
  `c:Ecto.Schema.__schema__/1`. Schema-less queries and schemas without primary
  keys cannot be proven deterministic by this check, so ordered queries in those
  cases return an issue unless validation is explicitly disabled.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type field_set :: list(atom())
  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:deterministic_order, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :deterministic_order
  def name, do: :deterministic_order

  @doc """
  Validates deterministic root `order_by` keys for a prepared Ecto query.

  Queries without `order_by` clauses are ignored. For ordered queries, the root
  ordered fields must include every field in the root schema primary key.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    cond do
      disabled?(check_opts) ->
        :ok

      ordered?(query) ->
        validate_ordered_query(operation, query)

      true ->
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

  defp disabled?(opts), do: Keyword.get(opts, :validate, true) == false

  defp validate_ordered_query(operation, query) do
    fields = order_fields(query)
    primary_key = primary_key(query)

    if deterministic?(fields, primary_key) do
      :ok
    else
      {:error, issue(operation, fields, primary_key)}
    end
  end

  defp primary_key(query) do
    case root_schema(query) do
      {:ok, schema} ->
        schema.__schema__(:primary_key)

      :unknown ->
        []
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

  defp ordered?(%{order_bys: order_bys}) when is_list(order_bys), do: not Enum.empty?(order_bys)
  defp ordered?(_query), do: false

  @spec order_fields(term()) :: field_set()
  defp order_fields(query) when is_map(query) do
    root_aliases = root_aliases(query)

    query
    |> Map.get(:order_bys, [])
    |> Enum.flat_map(fn order_by ->
      order_by |> Map.get(:expr, []) |> fields_in_order_expr(root_aliases)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp order_fields(_query), do: []

  defp root_aliases(query) do
    query
    |> Map.get(:aliases, %{})
    |> Enum.flat_map(fn
      {alias_name, 0} -> [alias_name]
      _alias -> []
    end)
    |> MapSet.new()
  end

  defp fields_in_order_expr(exprs, root_aliases) when is_list(exprs) do
    Enum.flat_map(exprs, fn
      {_direction, expr} -> direct_root_fields(expr, root_aliases)
      expr -> direct_root_fields(expr, root_aliases)
    end)
  end

  defp fields_in_order_expr(_expr, _root_aliases), do: []

  defp direct_root_fields({{:., _meta, [source, field]}, _call_meta, []}, root_aliases)
       when is_atom(field) do
    if root_binding?(source, root_aliases) do
      [field]
    else
      []
    end
  end

  defp direct_root_fields({:field, _meta, [source, field]}, root_aliases) when is_atom(field) do
    if root_binding?(source, root_aliases) do
      [field]
    else
      []
    end
  end

  defp direct_root_fields(_expr, _root_aliases), do: []

  defp root_binding?({:&, _meta, [0]}, _root_aliases), do: true

  defp root_binding?({:as, _meta, [alias_name]}, root_aliases) when is_atom(alias_name) do
    MapSet.member?(root_aliases, alias_name)
  end

  defp root_binding?(_expr, _root_aliases), do: false

  @spec deterministic?(field_set(), field_set()) :: boolean()
  defp deterministic?(_fields, []), do: false

  defp deterministic?(fields, primary_key) do
    Enum.all?(primary_key, &Enum.member?(fields, &1))
  end

  @spec issue(Bylaw.Ecto.Query.Check.operation(), field_set(), field_set()) :: Issue.t()
  defp issue(operation, fields, primary_key) do
    %Issue{
      check: __MODULE__,
      code: :non_deterministic_order,
      message: message(primary_key),
      meta: %{
        operation: operation,
        primary_key: primary_key,
        found_order_keys: fields
      }
    }
  end

  defp message([]) do
    "expected ordered query to include the root primary key, but no root primary key is known"
  end

  defp message(primary_key) do
    "expected ordered query to include the root primary key: #{format_keys(primary_key)}"
  end

  defp format_keys(keys), do: Enum.map_join(keys, ", ", &inspect/1)
end
