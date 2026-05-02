defmodule Bylaw.Ecto.Query.Checks.UnboundedDeletes do
  @moduledoc """
  Validates that `delete_all` queries include at least one root `where` clause.

  This check prevents accidental table-wide deletes by requiring callers to add
  an explicit `where` or `or_where` before `Repo.delete_all/2` runs:

      @bylaw [
        unbounded_deletes: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.UnboundedDeletes.validate(operation, query, bylaw_opts) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.delete_all(query, bylaw: [unbounded_deletes: [validate: false]])

  Supported options:

      [
        unbounded_deletes: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check only validates the root query prepared for the `:delete_all`
  operation. It requires at least one root `where` expression and does not try to
  prove whether that predicate is selective.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:unbounded_deletes, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :unbounded_deletes
  def name, do: :unbounded_deletes

  @doc """
  Validates that `:delete_all` operations include at least one root `where`.

  Non-delete operations always pass. For delete operations, any root `where` or
  `or_where` clause is accepted as the explicit bound.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.fetch!(opts, name(), [:validate])

    if CheckOptions.enabled?(check_opts) and unbounded_delete?(operation, query) do
      {:error, issue(operation)}
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp unbounded_delete?(:delete_all, query), do: not where?(query)
  defp unbounded_delete?(_operation, _query), do: false

  defp where?(%{wheres: wheres}) when is_list(wheres), do: Enum.any?(wheres)
  defp where?(_query), do: false

  @spec issue(Bylaw.Ecto.Query.Check.operation()) :: Issue.t()
  defp issue(operation) do
    %Issue{
      check: __MODULE__,
      message: "expected delete_all query to include at least one where clause",
      meta: %{
        operation: operation
      }
    }
  end
end
