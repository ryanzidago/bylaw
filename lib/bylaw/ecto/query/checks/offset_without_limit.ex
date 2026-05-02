defmodule Bylaw.Ecto.Query.Checks.OffsetWithoutLimit do
  @moduledoc """
  Validates that queries do not use `offset` without `limit`.

  Offset without limit skips rows and then returns every remaining row. That can
  create an unbounded scan from an arbitrary position, which is usually an
  accidental pagination shape:

      from post in Post,
        order_by: post.inserted_at,
        offset: 10_000

  Prefer pairing offset with a limit:

      from post in Post,
        order_by: post.inserted_at,
        limit: 50,
        offset: 10_000

      @bylaw [
        offset_without_limit: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.OffsetWithoutLimit.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [offset_without_limit: [validate: false]])

  Supported options:

      [
        offset_without_limit: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check applies to the root query and nested source subqueries, join
  subqueries, CTE queries, and combination branches.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:offset_without_limit, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :offset_without_limit
  def name, do: :offset_without_limit

  @doc """
  Validates that a prepared Ecto query does not use `offset` without `limit`.

  The operation is kept as issue metadata. This check applies the same static
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.fetch!(opts, name(), [:validate])

    if CheckOptions.enabled?(check_opts) and offset_without_limit?(query) do
      {:error, issue(operation)}
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp offset_without_limit?(query) when is_map(query) do
    direct_offset_without_limit?(query) or
      query
      |> nested_queries()
      |> Enum.any?(&offset_without_limit?/1)
  end

  defp offset_without_limit?(_query), do: false

  defp direct_offset_without_limit?(query), do: offset?(query) and not limited?(query)

  defp offset?(%{offset: nil}), do: false
  defp offset?(%{offset: offset}), do: expression_present?(offset)
  defp offset?(_query), do: false

  defp limited?(%{limit: nil}), do: false
  defp limited?(%{limit: limit}), do: expression_present?(limit)
  defp limited?(_query), do: false

  defp expression_present?(%{expr: expr, params: params}) when is_list(params) do
    expression_present?(expr, params)
  end

  defp expression_present?(%{expr: expr}) do
    expression_present?(expr, [])
  end

  defp expression_present?(_expr), do: true

  defp expression_present?(nil, _params), do: false

  defp expression_present?({:^, _meta, [index]}, params) when is_integer(index) do
    case Enum.fetch(params, index) do
      {:ok, param} -> not nil_param?(param)
      :error -> true
    end
  end

  defp expression_present?({:type, _meta, [expr, _type]}, params) do
    expression_present?(expr, params)
  end

  defp expression_present?(_expr, _params), do: true

  defp nil_param?({nil, _type}), do: true
  defp nil_param?(nil), do: true
  defp nil_param?(_param), do: false

  defp nested_queries(query) do
    source_queries(query) ++
      join_queries(query) ++
      cte_queries(query) ++ combination_queries(query) ++ expression_subquery_queries(query)
  end

  defp source_queries(%{from: %{source: source}}), do: subquery_source_queries(source)
  defp source_queries(_query), do: []

  defp join_queries(%{joins: joins}) when is_list(joins) do
    Enum.flat_map(joins, fn
      %{source: source} -> subquery_source_queries(source)
      _join -> []
    end)
  end

  defp join_queries(_query), do: []

  defp cte_queries(%{with_ctes: %{queries: queries}}) when is_list(queries) do
    Enum.flat_map(queries, fn
      {_name, _opts, query} -> [query]
      _cte -> []
    end)
  end

  defp cte_queries(_query), do: []

  defp combination_queries(%{combinations: combinations}) when is_list(combinations) do
    Enum.flat_map(combinations, fn
      {_operation, query} -> [query]
      _combination -> []
    end)
  end

  defp combination_queries(_query), do: []

  defp expression_subquery_queries(query) do
    Enum.flat_map(
      [:distinct, :select, :wheres, :havings, :order_bys, :group_bys, :windows],
      fn field ->
        query
        |> Map.get(field)
        |> expression_subqueries()
      end
    )
  end

  defp expression_subqueries(expressions) when is_list(expressions) do
    Enum.flat_map(expressions, &expression_subqueries/1)
  end

  defp expression_subqueries({_name, expression}), do: expression_subqueries(expression)

  defp expression_subqueries(%{subqueries: subqueries}) when is_list(subqueries) do
    Enum.flat_map(subqueries, &subquery_source_queries/1)
  end

  defp expression_subqueries(_expression), do: []

  defp subquery_source_queries(%{__struct__: Ecto.SubQuery, query: query}), do: [query]
  defp subquery_source_queries(_source), do: []

  @spec issue(Bylaw.Ecto.Query.Check.operation()) :: Issue.t()
  defp issue(operation) do
    %Issue{
      check: __MODULE__,
      message: "expected query with offset to include limit",
      meta: %{
        operation: operation,
        reason: :offset_without_limit
      }
    }
  end
end
