defmodule Bylaw.Ecto.Query.Checks.CartesianJoins do
  @moduledoc """
  Validates that queries do not use explicit cartesian joins.

  This check catches join shapes that are easy to introduce accidentally and
  expensive to run:

      from post in Post,
        join: comment in Comment,
        on: true

  It rejects `cross_join`, uncorrelated `cross_lateral_join`, and
  non-association joins whose `on` expression is literally `true`. Correlated
  lateral subqueries are treated as constrained when a supported subquery
  predicate compares a local subquery binding with a previous parent binding.

      @bylaw [
        cartesian_joins: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.CartesianJoins.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [cartesian_joins: [validate: false]])

  Supported options:

      [
        cartesian_joins: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  Like Bylaw's other Ecto query checks, this reads Ecto query structs directly.
  Ecto treats those structs as opaque, so this check intentionally supports a
  small, tested subset of Ecto's query AST. Association joins are not considered
  literal `on: true` joins because Ecto stores their association predicate
  separately from the `on` expression.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type reason :: :cross_join | :cross_lateral_join | :literal_true_on
  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:cartesian_joins, check_opts()})
  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]
  @lateral_quals [:cross_lateral, :inner_lateral, :left_lateral]

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :cartesian_joins
  def name, do: :cartesian_joins

  @doc """
  Validates that a prepared Ecto query does not contain cartesian joins.

  The operation is kept as issue metadata. This check applies the same join
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      check_opts = check_opts!(opts)

      if enabled?(check_opts) do
        validate_enabled(operation, query)
      else
        :ok
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

  defp validate_check_opt!({:validate, _value}), do: :ok

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp validate_enabled(operation, query) do
    case issues(operation, query) do
      [] -> :ok
      [issue] -> {:error, issue}
      issues -> {:error, issues}
    end
  end

  defp issues(operation, query) when is_map(query) do
    aliases = query_aliases(query)

    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      binding_index = join_index + 1

      case cartesian_reason(join, aliases, binding_index) do
        nil -> []
        reason -> [issue(operation, join, join_index, reason)]
      end
    end)
  end

  defp issues(_operation, _query), do: []

  defp query_aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  defp query_aliases(_query), do: %{}

  defp cartesian_reason(join, aliases, binding_index) do
    cond do
      correlated_lateral_join?(join, aliases, binding_index) -> nil
      match?(%{qual: :cross}, join) -> :cross_join
      match?(%{qual: :cross_lateral}, join) -> :cross_lateral_join
      association_join?(join) -> nil
      true -> literal_true_on_reason(join)
    end
  end

  defp association_join?(%{assoc: nil}), do: false
  defp association_join?(%{assoc: _assoc}), do: true
  defp association_join?(_join), do: false

  defp correlated_lateral_join?(
         %{qual: qual, source: %Ecto.SubQuery{query: query}},
         aliases,
         binding_index
       )
       when qual in @lateral_quals do
    correlated_lateral_query?(query, aliases, binding_index)
  end

  defp correlated_lateral_join?(_join, _aliases, _binding_index), do: false

  defp correlated_lateral_query?(query, parent_aliases, parent_binding_index)
       when is_map(query) do
    local_aliases = query_aliases(query)

    query
    |> predicate_expressions()
    |> Enum.any?(&correlated_predicate?(&1, parent_aliases, parent_binding_index, local_aliases))
  end

  defp correlated_lateral_query?(_query, _parent_aliases, _parent_binding_index), do: false

  defp predicate_expressions(query) do
    where_expressions(query) ++ join_on_expressions(query)
  end

  defp where_expressions(query) do
    query
    |> Map.get(:wheres, [])
    |> Enum.flat_map(fn
      %{expr: expr} -> [expr]
      _where -> []
    end)
  end

  defp join_on_expressions(query) do
    query
    |> Map.get(:joins, [])
    |> Enum.flat_map(fn
      %{on: %{expr: expr}} -> [expr]
      _join -> []
    end)
  end

  defp correlated_predicate?({:and, _meta, [left, right]}, parent_aliases, binding_index, aliases) do
    correlated_predicate?(left, parent_aliases, binding_index, aliases) or
      correlated_predicate?(right, parent_aliases, binding_index, aliases)
  end

  defp correlated_predicate?({:or, _meta, [left, right]}, parent_aliases, binding_index, aliases) do
    correlated_predicate?(left, parent_aliases, binding_index, aliases) and
      correlated_predicate?(right, parent_aliases, binding_index, aliases)
  end

  defp correlated_predicate?({op, _meta, [left, right]}, parent_aliases, binding_index, aliases)
       when op in @comparison_ops do
    correlated_comparison?(left, right, parent_aliases, binding_index, aliases)
  end

  defp correlated_predicate?(_expr, _parent_aliases, _binding_index, _aliases), do: false

  defp correlated_comparison?(left, right, parent_aliases, binding_index, aliases) do
    (parent_field?(left, parent_aliases, binding_index) and local_field?(right, aliases)) or
      (local_field?(left, aliases) and parent_field?(right, parent_aliases, binding_index))
  end

  defp parent_field?(expr, aliases, binding_index) do
    match?({_parent_index, _field}, parent_field(expr, aliases, binding_index))
  end

  defp parent_field({{:., _meta, [source, field]}, _call_meta, []}, aliases, binding_index)
       when is_atom(field) do
    parent_field(source, field, aliases, binding_index)
  end

  defp parent_field({:field, _meta, [source, field]}, aliases, binding_index)
       when is_atom(field) do
    parent_field(source, field, aliases, binding_index)
  end

  defp parent_field(_expr, _aliases, _binding_index), do: :unknown

  defp parent_field({:parent_as, _meta, [name]}, field, aliases, binding_index)
       when is_atom(name) do
    case Map.get(aliases, name) do
      index when is_integer(index) and index < binding_index -> {index, field}
      _index -> :unknown
    end
  end

  defp parent_field(_source, _field, _aliases, _binding_index), do: :unknown

  defp local_field?(expr, aliases) do
    match?({_local_index, _field}, local_field(expr, aliases))
  end

  defp local_field({{:., _meta, [source, field]}, _call_meta, []}, aliases)
       when is_atom(field) do
    local_field(source, field, aliases)
  end

  defp local_field({:field, _meta, [source, field]}, aliases) when is_atom(field) do
    local_field(source, field, aliases)
  end

  defp local_field(_expr, _aliases), do: :unknown

  defp local_field(source, field, aliases) do
    case local_binding_index(source, aliases) do
      index when is_integer(index) -> {index, field}
      :unknown -> :unknown
    end
  end

  defp local_binding_index({:&, _meta, [index]}, _aliases) when is_integer(index) do
    index
  end

  defp local_binding_index({:as, _meta, [name]}, aliases) when is_atom(name) do
    Map.get(aliases, name, :unknown)
  end

  defp local_binding_index(_source, _aliases), do: :unknown

  defp literal_true_on_reason(%{on: %{expr: true}}), do: :literal_true_on
  defp literal_true_on_reason(_join), do: nil

  @spec issue(Bylaw.Ecto.Query.Check.operation(), term(), non_neg_integer(), reason()) ::
          Issue.t()
  defp issue(operation, join, join_index, reason) do
    %Issue{
      check: __MODULE__,
      message: message(join_index, reason),
      meta: %{
        operation: operation,
        join_index: join_index,
        binding_index: join_index + 1,
        join_qual: Map.get(join, :qual),
        reason: reason
      }
    }
  end

  defp message(join_index, :cross_join) do
    "expected join #{join_index} not to be cartesian; found cross_join"
  end

  defp message(join_index, :cross_lateral_join) do
    "expected join #{join_index} not to be cartesian; found cross_lateral_join"
  end

  defp message(join_index, :literal_true_on) do
    "expected join #{join_index} not to be cartesian; found a literal true on expression"
  end
end
