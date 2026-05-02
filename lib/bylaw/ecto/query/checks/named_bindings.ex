defmodule Bylaw.Ecto.Query.Checks.NamedBindings do
  @moduledoc """
  Validates that an `Ecto.Query` uses named binding aliases in query expressions.

  This check reads the prepared Ecto query struct. It requires the root binding
  and every join to declare an `:as` alias, then rejects positional field
  references such as `post.id` or `field(post, :id)` after Ecto has expanded
  them to `&0.id` or `field(&0, :id)`.

  Association join sources, joined preloads, and whole-binding selects are not
  rejected because Ecto either requires binding variables for those forms or
  erases the source syntax before this check runs.

      query =
        from(post in Post,
          as: :post,
          where: as(:post).organisation_id == ^organisation_id
        )

      Bylaw.Ecto.Query.Checks.NamedBindings.validate(:all, query, [])

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [named_bindings: [validate: false]])

  Supported options:

      [
        named_bindings: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:named_bindings, check_opts()})
  @type expression_source :: %{
          macro: atom(),
          expr: term(),
          line: pos_integer() | nil,
          file: String.t() | nil,
          meta: map(),
          subqueries: list(term())
        }
  @type positional_reference :: %{
          binding_index: non_neg_integer(),
          field: atom() | term(),
          reference: :field_access | :field
        }

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :named_bindings
  def name, do: :named_bindings

  @doc """
  Validates named binding aliases and references for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same query
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = check_opts!(opts)

    if enabled?(check_opts) do
      case issues(operation, query) do
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

  defp validate_check_opt!({:validate, _value}), do: :ok

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp issues(operation, query) when is_map(query) do
    aliases = query_aliases(query)
    aliases_by_index = aliases_by_index(aliases)

    root_as_issues(operation, query, aliases_by_index) ++
      join_as_issues(operation, query) ++
      expression_reference_issues(operation, query, aliases_by_index) ++
      subquery_issues(operation, query)
  end

  defp issues(_operation, _query), do: []

  defp query_aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  defp query_aliases(_query), do: %{}

  defp aliases_by_index(aliases) do
    Enum.reduce(aliases, %{}, fn
      {name, binding_index}, aliases_by_index
      when is_atom(name) and is_integer(binding_index) ->
        Map.put_new(aliases_by_index, binding_index, name)

      _entry, aliases_by_index ->
        aliases_by_index
    end)
  end

  defp root_as_issues(operation, query, aliases_by_index) do
    if Map.has_key?(aliases_by_index, 0) or is_nil(Map.get(query, :from)) do
      []
    else
      [
        issue(
          "expected Ecto query root binding to declare an :as alias",
          :missing_root_as,
          operation,
          query,
          %{binding: :root}
        )
      ]
    end
  end

  defp join_as_issues(operation, query) do
    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      if is_nil(Map.get(join, :as)) do
        [
          issue(
            "expected Ecto query join binding to declare an :as alias",
            :missing_join_as,
            operation,
            join,
            %{join_index: join_index, binding_index: join_index + 1}
          )
        ]
      else
        []
      end
    end)
  end

  defp expression_reference_issues(operation, query, aliases_by_index) do
    query
    |> expression_sources()
    |> Enum.flat_map(fn source ->
      source.expr
      |> positional_references()
      |> Enum.map(&positional_reference_issue(operation, source, &1, aliases_by_index))
    end)
  end

  defp expression_sources(query) do
    boolean_expression_sources(:where, Map.get(query, :wheres, [])) ++
      boolean_expression_sources(:having, Map.get(query, :havings, [])) ++
      join_expression_sources(Map.get(query, :joins, [])) ++
      select_expression_sources(Map.get(query, :select)) ++
      by_expression_sources(:order_by, Map.get(query, :order_bys, [])) ++
      by_expression_sources(:group_by, Map.get(query, :group_bys, [])) ++
      distinct_expression_sources(Map.get(query, :distinct)) ++
      query_expression_sources(:update, Map.get(query, :updates, [])) ++
      window_expression_sources(Map.get(query, :windows, []))
  end

  defp boolean_expression_sources(name, expressions) do
    query_expression_sources(name, expressions)
  end

  defp join_expression_sources(joins) do
    joins
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      join
      |> Map.get(:on)
      |> expression_source(:join_on, %{join_index: join_index, binding_index: join_index + 1})
      |> List.wrap()
    end)
  end

  defp select_expression_sources(nil), do: []

  defp select_expression_sources(select) do
    List.wrap(expression_source(select, :select, %{}))
  end

  defp by_expression_sources(name, expressions) do
    query_expression_sources(name, expressions)
  end

  defp distinct_expression_sources(nil), do: []

  defp distinct_expression_sources(distinct) do
    List.wrap(expression_source(distinct, :distinct, %{}))
  end

  defp query_expression_sources(name, expressions) do
    Enum.flat_map(expressions, fn expression ->
      expression
      |> expression_source(name, %{})
      |> List.wrap()
    end)
  end

  defp window_expression_sources(windows) do
    Enum.flat_map(windows, fn {name, expression} ->
      expression
      |> expression_source(:windows, %{window: name})
      |> List.wrap()
    end)
  end

  defp expression_source(nil, _name, _meta), do: nil

  defp expression_source(%{expr: expr} = source, name, meta) do
    %{
      macro: name,
      expr: expr,
      line: Map.get(source, :line),
      file: Map.get(source, :file),
      meta: meta,
      subqueries: Map.get(source, :subqueries, [])
    }
  end

  @spec positional_references(term()) :: list(positional_reference())
  defp positional_references(
         {{:., _meta, [{:&, _binding_meta, [binding_index]}, field]}, _call_meta, []}
       )
       when is_integer(binding_index) do
    [
      %{
        binding_index: binding_index,
        field: field,
        reference: :field_access
      }
    ]
  end

  defp positional_references({:field, _meta, [{:&, _binding_meta, [binding_index]}, field]})
       when is_integer(binding_index) do
    [
      %{
        binding_index: binding_index,
        field: field,
        reference: :field
      }
    ]
  end

  defp positional_references({:^, _meta, [_expr]}), do: []
  defp positional_references({:as, _meta, [_name]}), do: []
  defp positional_references({:parent_as, _meta, [_name]}), do: []

  defp positional_references(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> positional_references()
  end

  defp positional_references(list) when is_list(list) do
    Enum.flat_map(list, &positional_references/1)
  end

  defp positional_references(_expr), do: []

  defp subquery_issues(operation, query) do
    query
    |> subqueries()
    |> Enum.flat_map(&issues(operation, &1))
  end

  defp subqueries(query) do
    expression_subqueries(query) ++ join_source_subqueries(query) ++ from_source_subqueries(query)
  end

  defp expression_subqueries(query) do
    query
    |> expression_sources()
    |> Enum.flat_map(& &1.subqueries)
    |> Enum.flat_map(&subquery_query/1)
  end

  defp join_source_subqueries(query) do
    query
    |> Map.get(:joins, [])
    |> Enum.flat_map(fn join ->
      join
      |> Map.get(:source)
      |> subquery_query()
    end)
  end

  defp from_source_subqueries(query) do
    query
    |> Map.get(:from)
    |> case do
      %{source: source} -> subquery_query(source)
      _from -> []
    end
  end

  defp subquery_query(%{__struct__: Ecto.SubQuery, query: query}) when is_map(query), do: [query]
  defp subquery_query(_source), do: []

  defp positional_reference_issue(operation, source, reference, aliases_by_index) do
    binding_index = reference.binding_index
    binding_alias = Map.get(aliases_by_index, binding_index)

    issue(
      positional_reference_message(source.macro, binding_index, binding_alias),
      :positional_binding_reference,
      operation,
      source,
      Map.merge(source.meta, %{
        macro: source.macro,
        binding_index: binding_index,
        binding_alias: binding_alias,
        field: reference.field,
        reference: reference.reference
      })
    )
  end

  defp positional_reference_message(macro, binding_index, nil) do
    "expected Ecto query #{macro} field reference on binding #{binding_index} to use as(:name) or parent_as(:name)"
  end

  defp positional_reference_message(macro, _binding_index, binding_alias) do
    "expected Ecto query #{macro} field reference on binding #{inspect(binding_alias)} to use as(:name) or parent_as(:name)"
  end

  defp issue(message, reason, operation, meta_source, extra_meta) do
    %Issue{
      check: __MODULE__,
      message: message,
      meta:
        %{
          operation: operation,
          reason: reason,
          line: line(meta_source),
          file: file(meta_source)
        }
        |> Map.merge(extra_meta)
    }
  end

  defp line(%{line: line}), do: line
  defp line(_value), do: nil

  defp file(%{file: file}), do: file
  defp file(_value), do: nil
end
