defmodule Bylaw.Ecto.Query.Checks.CartesianJoins do
  @moduledoc """
  Validates that queries do not use explicit cartesian joins.

  This check catches join shapes that are easy to introduce accidentally and
  expensive to run.

  ## Examples

  Bad:

      Post
      |> from(as: :post)
      |> join(:inner, [post: post], comment in Comment,
        as: :comment,
        on: true
      )

  Why this is bad:

  `on: true` creates every possible pair of posts and comments. That can
  multiply rows, inflate aggregates, and produce a query that is much more
  expensive than intended.

  Better:

      Post
      |> from(as: :post)
      |> join(:inner, [post: post], comment in Comment,
        as: :comment,
        on: comment.post_id == post.id
      )

  Why this is better:

  The join predicate states the relationship between the two tables, so each
  joined row is tied back to its post.

  Bad:

      Plan
      |> from(as: :plan)
      |> join(:cross, [plan: plan], feature in Feature, as: :feature)
      |> where([feature: feature], feature.enabled == true)

  ## Notes

  This check catches obvious cartesian joins: `cross_join`, uncorrelated
  `cross_lateral_join`, and non-association joins whose `on` expression is
  literally `true`. It does not parse SQL fragments or prove general SQL
  cardinality.

  It rejects `cross_join`, uncorrelated `cross_lateral_join`, and
  non-association joins whose `on` expression is literally `true`. Correlated
  lateral joins are treated as constrained when a supported subquery predicate
  depends on both a local subquery binding and a previous parent binding, or
  when a lateral fragment source exposes a previous parent binding reference.

  ## Options

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  Like Bylaw's other Ecto query checks, this intentionally inspects the query
  structure produced by Ecto's query macros. It supports the tested join and
  lateral subquery shapes exposed by the Ecto query API. Association joins are
  not considered literal `on: true` joins because Ecto stores their association
  predicate separately from the `on` expression.

  This check is a guardrail for obvious cartesian joins, not a full SQL
  cardinality proof. It does not parse fragment SQL. For lateral fragments, an
  Ecto-visible reference to a previous binding is treated as dependency
  evidence; opaque SQL that needs stricter review should be handled in the
  application query or by disabling the check for that call site.

  ## Usage

  Add this module to the checks passed to `Bylaw.Ecto.Query.validate/3`.
  See the README usage section for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @typedoc false
  @type reason :: :cross_join | :cross_lateral_join | :literal_true_on
  @typedoc false
  @type check_opts :: list({:validate, boolean()})
  @typedoc false
  @type opts :: check_opts()
  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]
  @lateral_quals [:cross_lateral, :inner_lateral, :left_lateral]

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate])

    if CheckOptions.enabled?(check_opts) do
      validate_enabled(operation, query)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_enabled(operation, query) do
    case issues(operation, query) do
      [] -> :ok
      issues -> {:error, issues}
    end
  end

  defp issues(operation, query) when is_map(query) do
    aliases = Introspection.aliases(query)

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

  defp correlated_lateral_join?(
         %{qual: qual, source: {:fragment, _meta, _parts} = source},
         aliases,
         binding_index
       )
       when qual in @lateral_quals do
    previous_binding_reference?(source, aliases, binding_index)
  end

  defp correlated_lateral_join?(_join, _aliases, _binding_index), do: false

  defp correlated_lateral_query?(query, parent_aliases, parent_binding_index)
       when is_map(query) do
    local_aliases = Introspection.aliases(query)

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

  defp correlated_predicate?(
         {:fragment, _meta, _parts} = expr,
         parent_aliases,
         binding_index,
         aliases
       ) do
    correlated_expression?(expr, parent_aliases, binding_index, aliases)
  end

  defp correlated_predicate?(_expr, _parent_aliases, _binding_index, _aliases), do: false

  defp correlated_comparison?(left, right, parent_aliases, binding_index, aliases) do
    correlated_expression?([left, right], parent_aliases, binding_index, aliases)
  end

  defp correlated_expression?(expr, parent_aliases, binding_index, aliases) do
    expr
    |> expression_references(parent_aliases, binding_index, aliases)
    |> correlated_references?()
  end

  defp correlated_references?(%{local?: true, parent?: true}), do: true
  defp correlated_references?(_references), do: false

  defp expression_references(expr, parent_aliases, binding_index, aliases) do
    cond do
      parent_field?(expr, parent_aliases, binding_index) ->
        %{local?: false, parent?: true}

      local_field?(expr, aliases) ->
        %{local?: true, parent?: false}

      is_tuple(expr) ->
        expr
        |> Tuple.to_list()
        |> expression_references(parent_aliases, binding_index, aliases)

      is_list(expr) ->
        Enum.reduce(expr, empty_references(), fn item, references ->
          merge_references(
            references,
            expression_references(item, parent_aliases, binding_index, aliases)
          )
        end)

      true ->
        empty_references()
    end
  end

  defp empty_references, do: %{local?: false, parent?: false}

  defp merge_references(left, right) do
    %{
      local?: left.local? or right.local?,
      parent?: left.parent? or right.parent?
    }
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
    match?({:ok, {_local_index, _field}}, Introspection.field(expr, aliases))
  end

  defp previous_binding_reference?(expr, aliases, binding_index) do
    previous_binding?(expr, aliases, binding_index) or
      previous_binding_field?(expr, aliases, binding_index) or
      nested_previous_binding_reference?(expr, aliases, binding_index)
  end

  defp previous_binding?(expr, aliases, binding_index) do
    case Introspection.binding_index(expr, aliases) do
      {:ok, index} when index < binding_index -> true
      _binding -> false
    end
  end

  defp previous_binding_field?(expr, aliases, binding_index) do
    case Introspection.field(expr, aliases) do
      {:ok, {index, _field}} when index < binding_index -> true
      _field -> false
    end
  end

  defp nested_previous_binding_reference?(expr, aliases, binding_index) when is_tuple(expr) do
    expr
    |> Tuple.to_list()
    |> previous_binding_reference?(aliases, binding_index)
  end

  defp nested_previous_binding_reference?(expr, aliases, binding_index) when is_list(expr) do
    Enum.any?(expr, &previous_binding_reference?(&1, aliases, binding_index))
  end

  defp nested_previous_binding_reference?(_expr, _aliases, _binding_index), do: false

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
