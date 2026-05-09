defmodule Bylaw.Ecto.Query.Checks.DuplicateJoins do
  @moduledoc """
  Validates that a query does not repeat equivalent joins.

  Duplicate joins make queries harder to reason about and can multiply rows or
  add avoidable database work. This check compares each join by its join kind,
  source or association, prefix, hints, source parameters, and normalized `on`
  expression. Named bindings are intentionally ignored, because a different
  binding name does not change the rows produced by the join.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> join(:inner, [post: p], c in Comment,
        as: :comment,
        on: c.post_id == p.id
      )
      |> join(:inner, [post: p], visible_c in Comment,
        as: :visible_comment,
        on: vc.post_id == p.id
      )

  Why this is bad:

  The same relationship appears twice. That can multiply rows and make later
  predicates ambiguous because each binding represents the same joined source.

  Better:

      from(Post, as: :post)
      |> join(:inner, [post: p], c in Comment,
        as: :comment,
        on: c.post_id == p.id
      )
      |> where([comment: c], c.visible == true)

  Why this is better:

  One join represents the relationship once, and predicates that refine the
  joined rows use that binding.

  ## Notes

  This check compares supported Ecto join shapes after normalization. It is not
  a semantic SQL equivalence engine.

  The check is static and intentionally inspects the query structure produced by
  Ecto's query macros. It supports the tested join shapes exposed by the Ecto
  query API.

  ## Options

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  ## Usage

  Add this module to the checks passed to `Bylaw.Ecto.Query.validate/3`.
  See the README usage section for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @metadata_keys [:file, :line, :cache]

  @typedoc false
  @type check_opts :: list({:validate, boolean()})
  @typedoc false
  @type opts :: check_opts()
  @typedoc false
  @type join_summary :: %{
          binding_index: pos_integer(),
          join_index: non_neg_integer()
        }
  @typedoc false
  @type normalize_context :: %{
          aliases: map(),
          binding_index: pos_integer() | nil,
          params: map(),
          subqueries: map()
        }

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
    case duplicate_issues(operation, query) do
      [] -> :ok
      issues -> {:error, issues}
    end
  end

  defp duplicate_issues(operation, %{joins: joins} = query) when is_list(joins) do
    aliases = Introspection.aliases(query)
    predicate_usages = predicate_usages_by_binding(query, joins, aliases)

    {_seen, issues} =
      joins
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {join, join_index}, {seen, issues} ->
        binding_index = join_index + 1
        signature = join_signature(join, binding_index, aliases, predicate_usages)

        case Map.fetch(seen, signature) do
          {:ok, original} ->
            issue = issue(operation, join, join_index, binding_index, original)
            {seen, [issue | issues]}

          :error ->
            {Map.put(seen, signature, join_summary(join_index, binding_index)), issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp duplicate_issues(_operation, _query), do: []

  defp join_signature(join, binding_index, aliases, predicate_usages) do
    context = normalize_context(binding_index, aliases)

    {
      Map.get(join, :qual),
      normalize_static_term(Map.get(join, :source)),
      normalize_join_term(Map.get(join, :assoc), context),
      normalize_static_term(Map.get(join, :prefix)),
      normalize_static_term(Map.get(join, :hints, [])),
      normalize_query_expr(Map.get(join, :on), context),
      normalize_static_term(Map.get(join, :params, [])),
      Map.get(predicate_usages, binding_index, [])
    }
  end

  defp predicate_usages_by_binding(query, joins, aliases) do
    predicate_expressions = predicate_expressions(query)

    joins
    |> Enum.with_index(1)
    |> Map.new(fn {_join, binding_index} ->
      {binding_index, predicate_usage(predicate_expressions, binding_index, aliases)}
    end)
  end

  defp predicate_expressions(query) when is_map(query) do
    query_expressions(query, :wheres, :where) ++ query_expressions(query, :havings, :having)
  end

  defp query_expressions(query, key, name) do
    case Map.get(query, key, []) do
      expressions when is_list(expressions) -> Enum.map(expressions, &{name, &1})
      _other -> []
    end
  end

  defp predicate_usage(predicate_expressions, binding_index, aliases) do
    context = normalize_context(binding_index, aliases)

    predicate_expressions
    |> Enum.flat_map(fn {name, predicate_expression} ->
      predicate_context = %{
        context
        | params: normalize_on_params(Map.get(predicate_expression, :params, []), context),
          subqueries: normalize_subqueries(Map.get(predicate_expression, :subqueries, []))
      }

      predicate_expression
      |> Map.get(:expr)
      |> predicate_terms(Map.get(predicate_expression, :op, :and))
      |> Enum.filter(&binding_referenced?(&1, binding_index, aliases))
      |> Enum.map(fn term ->
        {name, Map.get(predicate_expression, :op, :and),
         normalize_join_term(term, predicate_context)}
      end)
    end)
    |> Enum.sort_by(&:erlang.term_to_binary/1)
  end

  defp predicate_terms({operator, _meta, [left, right]}, operator)
       when operator in [:and, :or] do
    predicate_terms(left, operator) ++ predicate_terms(right, operator)
  end

  defp predicate_terms(nil, _operator), do: []
  defp predicate_terms(expr, _operator), do: [expr]

  defp normalize_context(binding_index \\ nil, aliases \\ %{}, params \\ %{}, subqueries \\ %{}) do
    %{aliases: aliases, binding_index: binding_index, params: params, subqueries: subqueries}
  end

  @spec join_summary(non_neg_integer(), pos_integer()) :: join_summary()
  defp join_summary(join_index, binding_index) do
    %{
      join_index: join_index,
      binding_index: binding_index
    }
  end

  defp normalize_query_expr(%{expr: expr, params: params}, context) do
    context = %{context | params: normalize_on_params(params, context)}

    normalize_join_term(expr, context)
  end

  defp normalize_query_expr(expr, context) do
    normalize_join_term(expr, context)
  end

  defp normalize_on_params(params, context) when is_list(params) do
    params
    |> Enum.with_index()
    |> Map.new(fn
      {{value, type}, index} ->
        {index, {:param, value, normalize_param_type(type, %{context | params: %{}})}}

      {param, index} ->
        {index, normalize_join_term(param, %{context | params: %{}})}
    end)
  end

  defp normalize_on_params(params, context) do
    %{0 => normalize_join_term(params, %{context | params: %{}})}
  end

  defp normalize_subqueries(subqueries) when is_list(subqueries) do
    subqueries
    |> Enum.with_index()
    |> Map.new(fn {subquery, index} -> {index, normalize_static_term(subquery)} end)
  end

  defp normalize_subqueries(_subqueries), do: %{}

  defp normalize_param_type({source_binding_index, field}, context)
       when is_integer(source_binding_index) and is_atom(field) do
    {normalize_binding_index(source_binding_index, context), field}
  end

  defp normalize_param_type(type, context) do
    normalize_join_term(type, context)
  end

  defp normalize_join_term({:&, _meta, [binding_index]}, context)
       when is_integer(binding_index) do
    normalize_binding_index(binding_index, context)
  end

  defp normalize_join_term({:as, _meta, [alias_name]}, context) when is_atom(alias_name) do
    case Map.fetch(context.aliases, alias_name) do
      {:ok, binding_index} -> normalize_binding_index(binding_index, context)
      :error -> {:as, [], [alias_name]}
    end
  end

  defp normalize_join_term({:^, _meta, [index]}, context) when is_integer(index) do
    case Map.fetch(context.params, index) do
      {:ok, param} -> {:^, [], [param]}
      :error -> {:^, [], [index]}
    end
  end

  defp normalize_join_term({:subquery, index}, context) when is_integer(index) do
    case Map.fetch(context.subqueries, index) do
      {:ok, subquery} -> {:subquery, subquery}
      :error -> {:subquery, index}
    end
  end

  defp normalize_join_term({operator, meta, [left, right]}, context)
       when operator in [:and, :or] do
    operands =
      [left, right]
      |> Enum.flat_map(&normalize_boolean_operand(&1, operator, context))
      |> Enum.sort_by(&:erlang.term_to_binary/1)

    {operator, normalize_ast_meta(meta), operands}
  end

  defp normalize_join_term({operator, meta, [left, right]}, context) when operator == :== do
    operands = [
      normalize_join_term(left, context),
      normalize_join_term(right, context)
    ]

    operands = Enum.sort_by(operands, &:erlang.term_to_binary/1)

    {operator, normalize_ast_meta(meta), operands}
  end

  defp normalize_join_term({left, right}, context) do
    {
      normalize_join_term(left, context),
      normalize_join_term(right, context)
    }
  end

  defp normalize_join_term({left, middle, right}, context)
       when is_list(middle) and is_list(right) do
    {
      normalize_join_term(left, context),
      normalize_ast_meta(middle),
      normalize_join_term(right, context)
    }
  end

  defp normalize_join_term(tuple, context) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_join_term(&1, context))
    |> List.to_tuple()
  end

  defp normalize_join_term(list, context) when is_list(list) do
    Enum.map(list, &normalize_join_term(&1, context))
  end

  defp normalize_join_term(%struct{} = term, context) do
    normalized_map =
      term
      |> Map.from_struct()
      |> normalize_map(context, :join, metadata_keys(struct))

    {struct, normalized_map}
  end

  defp normalize_join_term(map, context) when is_map(map) do
    normalize_map(map, context, :join, [])
  end

  defp normalize_join_term(term, _context), do: term

  defp normalize_boolean_operand({operator, _meta, [left, right]}, operator, context) do
    normalize_boolean_operand(left, operator, context) ++
      normalize_boolean_operand(right, operator, context)
  end

  defp normalize_boolean_operand(expr, _operator, context),
    do: [normalize_join_term(expr, context)]

  defp binding_referenced?({:&, _meta, [referenced_binding_index]}, binding_index, _aliases)
       when is_integer(referenced_binding_index) do
    referenced_binding_index == binding_index
  end

  defp binding_referenced?({:as, _meta, [alias_name]}, binding_index, aliases)
       when is_atom(alias_name) do
    Map.get(aliases, alias_name) == binding_index
  end

  defp binding_referenced?({referenced_binding_index, field}, binding_index, _aliases)
       when is_integer(referenced_binding_index) and is_atom(field) do
    referenced_binding_index == binding_index
  end

  defp binding_referenced?(tuple, binding_index, aliases) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&binding_referenced?(&1, binding_index, aliases))
  end

  defp binding_referenced?(list, binding_index, aliases) when is_list(list) do
    Enum.any?(list, &binding_referenced?(&1, binding_index, aliases))
  end

  defp binding_referenced?(%_struct{} = term, binding_index, aliases) do
    term
    |> Map.from_struct()
    |> binding_referenced?(binding_index, aliases)
  end

  defp binding_referenced?(map, binding_index, aliases) when is_map(map) do
    Enum.any?(map, fn {key, value} ->
      binding_referenced?(key, binding_index, aliases) or
        binding_referenced?(value, binding_index, aliases)
    end)
  end

  defp binding_referenced?(_term, _binding_index, _aliases), do: false

  defp normalize_binding_index(binding_index, %{binding_index: binding_index}) do
    {:&, [], [:join]}
  end

  defp normalize_binding_index(binding_index, _context) do
    {:&, [], [binding_index]}
  end

  defp normalize_static_term({left, right}) do
    {normalize_static_term(left), normalize_static_term(right)}
  end

  defp normalize_static_term({left, middle, right}) when is_list(middle) and is_list(right) do
    {normalize_static_term(left), normalize_ast_meta(middle), normalize_static_term(right)}
  end

  defp normalize_static_term(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_static_term/1)
    |> List.to_tuple()
  end

  defp normalize_static_term(list) when is_list(list),
    do: Enum.map(list, &normalize_static_term/1)

  defp normalize_static_term(%struct{} = term) do
    {struct,
     term
     |> Map.from_struct()
     |> normalize_map(normalize_context(), :static, metadata_keys(struct))}
  end

  defp normalize_static_term(map) when is_map(map),
    do: normalize_map(map, normalize_context(), :static, [])

  defp normalize_static_term(term), do: term

  defp normalize_map(map, context, mode, drop_keys) do
    map
    |> Map.drop(drop_keys)
    |> Map.new(fn {key, value} ->
      normalized_value =
        case mode do
          :join -> normalize_join_term(value, context)
          :static -> normalize_static_term(value)
        end

      {key, normalized_value}
    end)
  end

  defp normalize_ast_meta(meta) when is_list(meta), do: []
  defp normalize_ast_meta(term), do: normalize_static_term(term)

  defp metadata_keys(struct) do
    if ecto_query_struct?(struct), do: @metadata_keys, else: []
  end

  defp ecto_query_struct?(struct) when struct in [Ecto.Query, Ecto.SubQuery], do: true

  defp ecto_query_struct?(struct) do
    struct
    |> Atom.to_string()
    |> String.starts_with?("Elixir.Ecto.Query.")
  end

  @spec issue(
          Bylaw.Ecto.Query.Check.operation(),
          term(),
          non_neg_integer(),
          pos_integer(),
          join_summary()
        ) :: Issue.t()
  defp issue(operation, join, join_index, binding_index, original) do
    %Issue{
      check: __MODULE__,
      message: message(join_index, original.join_index),
      meta: %{
        operation: operation,
        join_index: join_index,
        binding_index: binding_index,
        original_join_index: original.join_index,
        original_binding_index: original.binding_index,
        join_qual: Map.get(join, :qual),
        join_source: join_source(join),
        join_assoc: Map.get(join, :assoc)
      }
    }
  end

  defp join_source(join) do
    case Map.get(join, :source) do
      nil -> nil
      source -> source
    end
  end

  defp message(join_index, original_join_index) do
    "expected query not to repeat equivalent joins; join #{join_index} duplicates join #{original_join_index}"
  end
end
