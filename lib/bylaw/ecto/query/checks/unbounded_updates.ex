defmodule Bylaw.Ecto.Query.Checks.UnboundedUpdates do
  @moduledoc """
  Validates that `update_all` queries are bounded.

  This check is useful as a guard against accidentally updating every row in a
  table:

      @bylaw [
        unbounded_updates: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.UnboundedUpdates.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.update_all(query, updates, bylaw: [unbounded_updates: [validate: false]])

  Supported options:

      [
        unbounded_updates: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check only applies to the `:update_all` operation reported by
  `c:Ecto.Repo.prepare_query/3`. It accepts update queries with a restricting
  `where` clause or a filtered subquery joined back to the updated rows. Checks
  that need specific predicates should use a more targeted rule such as
  `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:unbounded_updates, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :unbounded_updates
  def name, do: :unbounded_updates

  @doc """
  Validates that `update_all` queries are bounded.

  Operations other than `:update_all` are ignored.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.fetch!(opts, name(), [:validate])

    if CheckOptions.enabled?(check_opts) and unbounded_update?(operation, query) do
      {:error, issue(operation)}
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp unbounded_update?(:update_all, query), do: not bounded_query?(query)
  defp unbounded_update?(_operation, _query), do: false

  defp bounded_query?(query) do
    where_clause?(query) or filtered_subquery_join?(query)
  end

  defp where_clause?(%{wheres: wheres}) when is_list(wheres) do
    Enum.any?(wheres, &restricting_where?/1)
  end

  defp where_clause?(_query), do: false

  defp restricting_where?(%{expr: true}), do: false
  defp restricting_where?(_where), do: true

  defp filtered_subquery_join?(%{joins: joins} = query) when is_list(joins) do
    aliases = Introspection.aliases(query)

    joins
    |> Enum.with_index()
    |> Enum.any?(fn {join, join_index} ->
      filtered_subquery_join_entry?(join, join_index + 1, aliases)
    end)
  end

  defp filtered_subquery_join?(_query), do: false

  defp filtered_subquery_join_entry?(
         %{
           source: %{__struct__: Ecto.SubQuery, query: subquery},
           on: %{expr: join_expr}
         },
         binding_index,
         aliases
       ) do
    where_clause?(subquery) and root_join_predicate?(join_expr, binding_index, aliases)
  end

  defp filtered_subquery_join_entry?(_join, _binding_index, _aliases), do: false

  defp root_join_predicate?(true, _binding_index, _aliases), do: false

  defp root_join_predicate?({:and, _meta, [left, right]}, binding_index, aliases) do
    root_join_predicate?(left, binding_index, aliases) or
      root_join_predicate?(right, binding_index, aliases)
  end

  defp root_join_predicate?({:or, _meta, [left, right]}, binding_index, aliases) do
    root_join_predicate?(left, binding_index, aliases) and
      root_join_predicate?(right, binding_index, aliases)
  end

  defp root_join_predicate?({:not, _meta, [expr]}, binding_index, aliases) do
    root_join_predicate?(expr, binding_index, aliases)
  end

  defp root_join_predicate?(expr, binding_index, aliases) do
    binding_indexes = binding_indexes(expr, aliases)

    MapSet.member?(binding_indexes, 0) and MapSet.member?(binding_indexes, binding_index)
  end

  defp binding_indexes(expr, aliases) do
    case Introspection.binding_index(expr, aliases) do
      {:ok, binding_index} -> MapSet.new([binding_index])
      :unknown -> nested_binding_indexes(expr, aliases)
    end
  end

  defp nested_binding_indexes(expr, aliases) when is_tuple(expr) do
    expr
    |> Tuple.to_list()
    |> nested_binding_indexes(aliases)
  end

  defp nested_binding_indexes(expr, aliases) when is_list(expr) do
    Enum.reduce(expr, MapSet.new(), fn item, indexes ->
      MapSet.union(indexes, binding_indexes(item, aliases))
    end)
  end

  defp nested_binding_indexes(_expr, _aliases), do: MapSet.new()

  @spec issue(Bylaw.Ecto.Query.Check.operation()) :: Issue.t()
  defp issue(operation) do
    %Issue{
      check: __MODULE__,
      message:
        "expected update_all query to be bounded by a where clause or filtered subquery join",
      meta: %{operation: operation}
    }
  end
end
