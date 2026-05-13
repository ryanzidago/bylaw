defmodule Bylaw.Ecto.Query.Checks.OffsetWithoutLimit do
  @moduledoc """
  Validates that queries do not use `offset` without `limit`.

  Offset without limit skips rows and then returns every remaining row. That can
  create an unbounded scan from an arbitrary position, which is usually an
  accidental pagination shape.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> order_by([post: p], asc: p.inserted_at)
      |> offset(10_000)

  Why this is bad:

  The query skips 10,000 rows and then returns every remaining row. That is
  usually an accidental unbounded pagination query.

  Better:

      from(Post, as: :post)
      |> order_by([post: p], asc: p.inserted_at)
      |> limit(50)
      |> offset(10_000)

  Why this is better:

  `limit` gives the page a bounded size. Pair this with
  `Bylaw.Ecto.Query.Checks.RequiredOrder` when the page also needs stable row
  order.

  ## Notes

  This check only verifies that `offset` has a paired `limit`. It does not prove
  the order is deterministic or that offset pagination is the best strategy for
  a large table.

  ## Options

    * `:validate` - explicit `false` disables this check. It can be used in the
      repo-wide check list or in call-site overrides passed to
      `Bylaw.Ecto.Query.validate/4`.

  Run globally with defaults:

      Bylaw.Ecto.Query.Checks.OffsetWithoutLimit

  Run only for matching rule scopes:

      {Bylaw.Ecto.Query.Checks.OffsetWithoutLimit,
       rules: [
         [where: [ecto_schemas: [Post]]],
         [where: [tables: ["posts"]]]
       ]}

  This check has no check-specific rule options.

  The check applies to the root query and nested source subqueries, join
  subqueries, CTE queries, combination branches, and expression subqueries.

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

    if CheckOptions.enabled?(check_opts) and
         RuleOptions.scoped?(check_opts, :offset_without_limit, operation, query) and
         offset_without_limit?(query) do
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
