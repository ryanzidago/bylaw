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
  `c:Ecto.Repo.prepare_query/3`. It requires every possible root `where` branch
  to include at least one non-literal-true expression. It does not prove whether
  that predicate is selective. Checks that need specific predicates should use a
  more targeted rule such as
  `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
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

  defp unbounded_update?(:update_all, query), do: not where_clause?(query)
  defp unbounded_update?(_operation, _query), do: false

  defp where_clause?(%{wheres: wheres}) when is_list(wheres) do
    wheres
    |> Enum.reduce(nil, &combine_where/2)
    |> restricting_filter?()
  end

  defp where_clause?(_query), do: false

  defp combine_where(%{expr: expr} = where, nil) do
    filter_type(expr, Map.get(where, :params, []))
  end

  defp combine_where(%{expr: expr, op: :or} = where, filter) do
    or_filter(filter, filter_type(expr, Map.get(where, :params, [])))
  end

  defp combine_where(%{expr: expr} = where, filter) do
    and_filter(filter, filter_type(expr, Map.get(where, :params, [])))
  end

  defp combine_where(_where, nil), do: :restricting
  defp combine_where(_where, filter), do: and_filter(filter, :restricting)

  defp filter_type(true, _params), do: :unrestricting
  defp filter_type(false, _params), do: :empty

  defp filter_type({:^, _meta, [index]}, params) when is_integer(index) do
    case Enum.fetch(params, index) do
      {:ok, {value, _type}} -> filter_type(value, [])
      {:ok, value} -> filter_type(value, [])
      :error -> :restricting
    end
  end

  defp filter_type(%Ecto.Query.Tagged{value: value}, _params), do: filter_type(value, [])
  defp filter_type({:type, _meta, [expr, _type]}, params), do: filter_type(expr, params)

  defp filter_type({:and, _meta, [left, right]}, params) do
    left
    |> filter_type(params)
    |> and_filter(filter_type(right, params))
  end

  defp filter_type({:or, _meta, [left, right]}, params) do
    left
    |> filter_type(params)
    |> or_filter(filter_type(right, params))
  end

  defp filter_type({:not, _meta, [expr]}, params) do
    expr
    |> filter_type(params)
    |> negate_filter()
  end

  defp filter_type(_expr, _params), do: :restricting

  defp and_filter(:empty, _right), do: :empty
  defp and_filter(_left, :empty), do: :empty
  defp and_filter(:unrestricting, :unrestricting), do: :unrestricting
  defp and_filter(_left, _right), do: :restricting

  defp or_filter(:unrestricting, _right), do: :unrestricting
  defp or_filter(_left, :unrestricting), do: :unrestricting
  defp or_filter(:empty, :empty), do: :empty
  defp or_filter(_left, _right), do: :restricting

  defp negate_filter(:unrestricting), do: :empty
  defp negate_filter(:empty), do: :unrestricting
  defp negate_filter(:restricting), do: :restricting

  defp restricting_filter?(nil), do: false
  defp restricting_filter?(:unrestricting), do: false
  defp restricting_filter?(_filter), do: true

  @spec issue(Bylaw.Ecto.Query.Check.operation()) :: Issue.t()
  defp issue(operation) do
    %Issue{
      check: __MODULE__,
      message: "expected update_all query to include at least one non-true root where clause",
      meta: %{operation: operation}
    }
  end
end
