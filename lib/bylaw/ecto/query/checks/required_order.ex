defmodule Bylaw.Ecto.Query.Checks.RequiredOrder do
  @moduledoc """
  Validates that query shapes requiring stable row order include `order_by`.

  This check only answers whether an `order_by` clause is required and present.
  It intentionally does not decide whether the existing order is deterministic;
  use `Bylaw.Ecto.Query.Checks.DeterministicOrder` for that separate question.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  Queries with `limit`, `offset`, or the `:stream` operation require an
  `order_by` clause. If any `order_by` exists, this check passes and leaves
  deterministic tie-breaker validation to `DeterministicOrder`.

  Ecto rewrites `Repo.exists?/2` queries to `select 1` with `limit 1`. This
  synthetic limit is ignored because existence checks do not depend on which row
  is returned. A preserved `offset` still requires ordering because the skipped
  rows are otherwise undefined.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @type reason :: :limit | :offset | :stream
  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()

  @doc """
  Validates required `order_by` presence for a prepared Ecto query.

  Queries with `limit`, `offset`, or the `:stream` operation must include an
  `order_by` clause. Existing `order_by` clauses are accepted without checking
  whether they are deterministic.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate])
    required_by = missing_order_reasons(operation, query)

    if CheckOptions.enabled?(check_opts) and not Enum.empty?(required_by) do
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
