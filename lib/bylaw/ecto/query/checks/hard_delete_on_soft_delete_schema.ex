defmodule Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchema do
  @moduledoc """
  Validates that soft-delete schemas are not hard-deleted with `delete_all`.

  Schemas that declare a persisted `:deleted_at` or `:archived_at` field usually
  expect lifecycle removal to be represented as an update. A bulk hard delete on
  that schema is therefore suspicious even when the query is otherwise bounded:

      from post in Post,
        where: post.status == ^:archived

  Prefer `Repo.update_all/3` setting `:deleted_at` or `:archived_at` instead of
  `Repo.delete_all/2` when this check reports an issue.

  The check is zero-config. Field presence in `__schema__(:fields)` is the
  signal. It is enabled by default, and a caller must explicitly set the
  query-level escape hatch to `false` to skip it:

      Repo.delete_all(query, bylaw: [{Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchema, validate: false}])

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The root query and every combination branch are inspected independently. The
  check ignores schema-less queries, non-query values, virtual fields, source
  subqueries, and soft-delete fields that appear only on joined schemas.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @soft_delete_fields [:deleted_at, :archived_at]

  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()

  @doc """
  Validates that `:delete_all` is not used for schemas with soft-delete fields.

  Non-delete operations always pass. For delete operations, the root schema must
  not declare persisted `:deleted_at` or `:archived_at` fields.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate])

    if CheckOptions.enabled?(check_opts) do
      validate_enabled(operation, query)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_enabled(:delete_all, query) do
    query
    |> Introspection.query_branches()
    |> Enum.flat_map(&issues_for_branch(:delete_all, &1))
    |> result()
  end

  defp validate_enabled(_operation, _query), do: :ok

  defp issues_for_branch(operation, {branch_path, query}) do
    with {:ok, schema} <- Introspection.root_schema(query),
         soft_delete_fields = soft_delete_fields(schema),
         false <- Enum.empty?(soft_delete_fields) do
      [issue(operation, schema, soft_delete_fields, branch_path)]
    else
      _not_applicable -> []
    end
  end

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
  defp result(issues), do: {:error, issues}

  defp soft_delete_fields(schema) do
    schema_fields = Introspection.schema_fields(schema)

    Enum.filter(@soft_delete_fields, &MapSet.member?(schema_fields, &1))
  end

  @spec issue(Bylaw.Ecto.Query.Check.operation(), module(), list(atom()), list()) :: Issue.t()
  defp issue(operation, schema, soft_delete_fields, branch_path) do
    %Issue{
      check: __MODULE__,
      message: "expected delete_all on schema with soft-delete fields to use update_all instead",
      meta:
        Map.merge(
          %{
            operation: operation,
            root_schema: schema,
            soft_delete_fields: soft_delete_fields
          },
          Introspection.combination_path_meta(branch_path)
        )
    }
  end
end
