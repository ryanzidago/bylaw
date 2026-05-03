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

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check applies to the root query and nested source subqueries, join
  subqueries, CTE queries, combination branches, and expression subqueries.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()

  @doc """
  Validates that a prepared Ecto query does not use `offset` without `limit`.

  The operation is kept as issue metadata. This check applies the same static
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate])

    if CheckOptions.enabled?(check_opts) and offset_without_limit?(query) do
      {:error, [issue(operation)]}
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
      |> Introspection.nested_queries()
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
