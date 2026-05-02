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
  to include at least one non-true expression. It does not prove whether that
  predicate is selective. Checks that need specific predicates should use a more
  targeted rule such as
  `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Boundedness
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

  defp unbounded_update?(:update_all, query), do: not Boundedness.root_where_bounded?(query)
  defp unbounded_update?(_operation, _query), do: false

  @spec issue(Bylaw.Ecto.Query.Check.operation()) :: Issue.t()
  defp issue(operation) do
    %Issue{
      check: __MODULE__,
      message: "expected update_all query to include at least one non-true root where clause",
      meta: %{operation: operation}
    }
  end
end
