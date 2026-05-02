defmodule Bylaw.Ecto.Query.Checks.DuplicateJoins do
  @moduledoc """
  Validates that a query does not repeat equivalent joins.

  Duplicate joins make queries harder to reason about and can multiply rows or
  add avoidable database work. This check compares each join by its join kind,
  source or association, prefix, hints, source parameters, and normalized `on`
  expression. Named bindings are intentionally ignored, because a different
  binding name does not change the rows produced by the join.

      @bylaw [
        duplicate_joins: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.DuplicateJoins.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [duplicate_joins: [validate: false]])

  Supported options:

      [
        duplicate_joins: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check is static and reads the Ecto query struct directly. Ecto treats
  query structs as opaque, so this check intentionally supports the tested join
  shapes exposed by Ecto's query macros.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:duplicate_joins, check_opts()})
  @type join_summary :: %{
          binding_index: pos_integer(),
          join_index: non_neg_integer()
        }

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :duplicate_joins
  def name, do: :duplicate_joins

  @doc """
  Validates that prepared Ecto queries do not contain equivalent joins.

  Queries without joins are ignored. When several joins repeat an earlier join,
  the check returns one issue per repeated join.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    if enabled?(check_opts) do
      validate_enabled(operation, query)
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
    case duplicate_issues(operation, query) do
      [] -> :ok
      [issue] -> {:error, issue}
      issues -> {:error, issues}
    end
  end

  defp duplicate_issues(operation, %{joins: joins}) when is_list(joins) do
    {_seen, issues} =
      joins
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {join, join_index}, {seen, issues} ->
        binding_index = join_index + 1
        signature = join_signature(join, binding_index)

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

  defp join_signature(join, binding_index) do
    {
      Map.get(join, :qual),
      normalize_static_term(Map.get(join, :source)),
      normalize_join_term(Map.get(join, :assoc), binding_index),
      normalize_static_term(Map.get(join, :prefix)),
      normalize_static_term(Map.get(join, :hints, [])),
      normalize_query_expr(Map.get(join, :on), binding_index),
      normalize_static_term(Map.get(join, :params, []))
    }
  end

  @spec join_summary(non_neg_integer(), pos_integer()) :: join_summary()
  defp join_summary(join_index, binding_index) do
    %{
      join_index: join_index,
      binding_index: binding_index
    }
  end

  defp normalize_query_expr(%{expr: expr, params: params}, binding_index) do
    {
      normalize_join_term(expr, binding_index),
      normalize_on_params(params, binding_index)
    }
  end

  defp normalize_query_expr(expr, binding_index) do
    normalize_join_term(expr, binding_index)
  end

  defp normalize_on_params(params, binding_index) when is_list(params) do
    Enum.map(params, fn
      {value, type} ->
        {normalize_static_term(value), normalize_param_type(type, binding_index)}

      param ->
        normalize_join_term(param, binding_index)
    end)
  end

  defp normalize_on_params(params, binding_index) do
    normalize_join_term(params, binding_index)
  end

  defp normalize_param_type({source_binding_index, field}, binding_index)
       when source_binding_index == binding_index and is_atom(field) do
    {:join, field}
  end

  defp normalize_param_type(type, binding_index) do
    normalize_join_term(type, binding_index)
  end

  defp normalize_join_term({:&, _meta, [binding_index]}, binding_index) do
    {:&, [], [:join]}
  end

  defp normalize_join_term({operator, meta, [left, right]}, binding_index)
       when operator in [:==, :and, :or] do
    operands =
      [normalize_join_term(left, binding_index), normalize_join_term(right, binding_index)]
      |> Enum.sort_by(&:erlang.term_to_binary/1)

    {operator, normalize_ast_meta(meta), operands}
  end

  defp normalize_join_term({left, right}, binding_index) do
    {
      normalize_join_term(left, binding_index),
      normalize_join_term(right, binding_index)
    }
  end

  defp normalize_join_term({left, middle, right}, binding_index) do
    {
      normalize_join_term(left, binding_index),
      normalize_ast_meta(middle),
      normalize_join_term(right, binding_index)
    }
  end

  defp normalize_join_term(tuple, binding_index) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_join_term(&1, binding_index))
    |> List.to_tuple()
  end

  defp normalize_join_term(list, binding_index) when is_list(list) do
    Enum.map(list, &normalize_join_term(&1, binding_index))
  end

  defp normalize_join_term(%struct{} = term, binding_index) do
    {struct, term |> Map.from_struct() |> normalize_map(binding_index, :join)}
  end

  defp normalize_join_term(map, binding_index) when is_map(map) do
    normalize_map(map, binding_index, :join)
  end

  defp normalize_join_term(term, _binding_index), do: term

  defp normalize_static_term({left, right}) do
    {normalize_static_term(left), normalize_static_term(right)}
  end

  defp normalize_static_term({left, middle, right}) do
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
    {struct, term |> Map.from_struct() |> normalize_map(nil, :static)}
  end

  defp normalize_static_term(map) when is_map(map), do: normalize_map(map, nil, :static)
  defp normalize_static_term(term), do: term

  defp normalize_map(map, binding_index, mode) do
    map
    |> Map.drop([:file, :line, :cache])
    |> Map.new(fn {key, value} ->
      normalized_value =
        case mode do
          :join -> normalize_join_term(value, binding_index)
          :static -> normalize_static_term(value)
        end

      {key, normalized_value}
    end)
  end

  defp normalize_ast_meta(meta) when is_list(meta), do: []
  defp normalize_ast_meta(term), do: normalize_static_term(term)

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
