defmodule Bylaw.Ecto.Query.Checks.RequiredOrder do
  @moduledoc """
  Validates that query shapes requiring stable row order include `order_by`.

  This check only answers whether an `order_by` clause is required and present.
  It intentionally does not decide whether the existing order is deterministic;
  use `Bylaw.Ecto.Query.Checks.DeterministicOrder` for that separate question.

      @bylaw [
        required_order: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.RequiredOrder.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [required_order: [validate: false]])

  Supported options:

      [
        required_order: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  Queries with `limit`, `offset`, or the `:stream` operation require an
  `order_by` clause. If any `order_by` exists, this check passes and leaves
  deterministic tie-breaker validation to `DeterministicOrder`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @type reason :: :limit | :offset | :stream
  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:required_order, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :required_order
  def name, do: :required_order

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
    check_opts = check_opts!(opts)
    required_by = required_by(operation, query)

    if enabled?(check_opts) and not Enum.empty?(required_by) and not ordered?(query) do
      {:error, issue(operation, required_by)}
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

  @spec required_by(Bylaw.Ecto.Query.Check.operation(), term()) :: list(reason())
  defp required_by(operation, query) do
    [
      {:limit, limited?(query)},
      {:offset, offset?(query)},
      {:stream, operation == :stream}
    ]
    |> Enum.flat_map(fn
      {reason, true} -> [reason]
      {_reason, false} -> []
    end)
  end

  defp limited?(%{limit: nil}), do: false
  defp limited?(%{limit: _limit}), do: true
  defp limited?(_query), do: false

  defp offset?(%{offset: nil}), do: false
  defp offset?(%{offset: _offset}), do: true
  defp offset?(_query), do: false

  defp ordered?(%{order_bys: order_bys}) when is_list(order_bys), do: not Enum.empty?(order_bys)
  defp ordered?(_query), do: false

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
