defmodule Bylaw.Ecto.Query.Checks.RequiredOrder do
  @moduledoc """
  Validates that query shapes requiring stable row order include `order_by`.

  This check only answers whether an `order_by` clause is required and present.
  It intentionally does not decide whether the existing order is deterministic;
  use `Bylaw.Ecto.Query.Checks.DeterministicOrder` for that separate question.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> limit(10)

  Why this is bad:

  A limited query without `order_by` asks the database for any matching 10 rows.
  Pagination, retries, and repeated calls can see rows appear, disappear, or
  move because the selected window has no stable order.

  Better:

      from(Post, as: :post)
      |> order_by([post: p], desc: p.inserted_at)
      |> limit(10)

  Why this is better:

  The selected window is taken from a declared order, so callers can reason
  about which rows are first.

  Bad:

      from(Post, as: :post)
      |> offset(50)
      |> limit(25)

  Why this is bad:

  `offset` skips an undefined set of rows when no order exists. Page boundaries
  can shift between executions.

  Better:

      from(Post, as: :post)
      |> order_by([post: p], desc: p.inserted_at)
      |> offset(50)
      |> limit(25)

  Why this is better:

  Rows are skipped from a known order, so the page boundary has a defined
  meaning.

  Bad:

      from(Post, as: :post)
      |> Repo.stream()

  Better:

      from(Post, as: :post)
      |> order_by([post: p], asc: p.id)
      |> Repo.stream()

  ## Notes

  This check only requires that some `order_by` exists. It does not prove that
  the order is deterministic. If rows can tie on the ordered field, pair this
  check with `DeterministicOrder` to require a primary-key tie-breaker:

      from(Post, as: :post)
      |> order_by([post: p], desc: p.inserted_at)
      |> order_by([post: p], asc: p.id)
      |> limit(10)

  Ecto rewrites `Repo.exists?/2` queries to `select 1` with `limit 1`. This
  synthetic limit is ignored because existence checks do not depend on which row
  is returned. A preserved `offset` still requires ordering because the skipped
  rows are otherwise undefined.

  ## Options

    * `:validate` - explicit `false` disables this check. It can be used in the
      repo-wide check list or in call-site overrides passed to
      `Bylaw.Ecto.Query.validate/4`.

  Run globally with defaults:

      Bylaw.Ecto.Query.Checks.RequiredOrder

  Run only for matching rule scopes:

      {Bylaw.Ecto.Query.Checks.RequiredOrder,
       rules: [
         [where: [ecto_schemas: [Post]]],
         [where: [tables: ["posts"]]]
       ]}

  This check has no check-specific rule options.

  Queries with `limit`, `offset`, or the `:stream` operation require an
  `order_by` clause. If any `order_by` exists, this check passes and leaves
  deterministic tie-breaker validation to `DeterministicOrder`.

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.Ecto.Query`.
  See `Bylaw.Ecto.Query` for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue
  alias Bylaw.Ecto.Query.RuleOptions

  @typedoc false
  @type reason :: :limit | :offset | :stream
  @typedoc false
  @type check_opts :: list({:validate, boolean()})
  @typedoc false
  @type opts :: check_opts()

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate, :rules])
    required_by = missing_order_reasons(operation, query)

    if CheckOptions.enabled?(check_opts) and
         RuleOptions.scoped?(check_opts, :required_order, operation, query) and
         not Enum.empty?(required_by) do
      {:error, [issue(operation, required_by)]}
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  @spec missing_order_reasons(Bylaw.Ecto.Query.Check.operation(), term()) :: list(reason())
  defp missing_order_reasons(operation, query) do
    direct_missing_order_reasons(operation, query)
    |> Enum.concat(nested_missing_order_reasons(query))
    |> Enum.uniq()
  end

  defp direct_missing_order_reasons(operation, query) do
    required_by =
      operation
      |> required_by(query)
      |> ignore_exists_limit(operation, query)

    cond do
      Enum.empty?(required_by) -> []
      ordered?(query) -> []
      true -> required_by
    end
  end

  @spec required_by(Bylaw.Ecto.Query.Check.operation(), term()) :: list(reason())
  defp required_by(operation, query) do
    Enum.flat_map(
      [
        {:limit, limited?(query)},
        {:offset, offset?(query)},
        {:stream, operation == :stream}
      ],
      fn
        {reason, true} -> [reason]
        {_reason, false} -> []
      end
    )
  end

  defp limited?(%{limit: nil}), do: false
  defp limited?(%{limit: _limit}), do: true
  defp limited?(_query), do: false

  defp offset?(%{offset: nil}), do: false
  defp offset?(%{offset: _offset}), do: true
  defp offset?(_query), do: false

  defp ordered?(%{order_bys: order_bys}) when is_list(order_bys) do
    Enum.any?(order_bys, fn
      %{expr: exprs} when is_list(exprs) -> not Enum.empty?(exprs)
      _order_by -> false
    end)
  end

  defp ordered?(_query), do: false

  defp exists_query?(:all, query) do
    literal_select?(query, 1) and literal_limit?(query, 1)
  end

  defp exists_query?(_operation, _query), do: false

  defp ignore_exists_limit(required_by, operation, query) do
    if exists_query?(operation, query) do
      List.delete(required_by, :limit)
    else
      required_by
    end
  end

  defp literal_select?(%{select: %{expr: value}}, value), do: true
  defp literal_select?(_query, _value), do: false

  defp literal_limit?(%{limit: %{expr: value}}, value), do: true
  defp literal_limit?(_query, _value), do: false

  defp nested_missing_order_reasons(query) do
    query
    |> Introspection.nested_queries()
    |> Enum.flat_map(&missing_order_reasons(:all, &1))
  end

  @spec issue(Bylaw.Ecto.Query.Check.operation(), list(reason())) :: Issue.t()
  defp issue(operation, required_by) do
    %Issue{
      check: __MODULE__,
      message: "expected query with #{format_reasons(required_by)} to include order_by",
      meta: %{
        operation: operation,
        required_by: required_by
      }
    }
  end

  defp format_reasons([reason]), do: format_reason(reason)

  defp format_reasons(reasons) do
    Enum.map_join(reasons, ", ", &format_reason/1)
  end

  defp format_reason(:limit), do: "limit"
  defp format_reason(:offset), do: "offset"
  defp format_reason(:stream), do: "stream operation"
end
