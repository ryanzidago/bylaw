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

      Repo.delete_all(query, bylaw: [hard_delete_on_soft_delete_schema: [validate: false]])

  Supported options:

      [
        hard_delete_on_soft_delete_schema: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  Only the root schema for the prepared `:delete_all` query is inspected. The
  check ignores schema-less queries, non-query values, virtual fields, and
  soft-delete fields that appear only on joined schemas.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @soft_delete_fields [:deleted_at, :archived_at]

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:hard_delete_on_soft_delete_schema, check_opts()})

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :hard_delete_on_soft_delete_schema
  def name, do: :hard_delete_on_soft_delete_schema

  @doc """
  Validates that `:delete_all` is not used for schemas with soft-delete fields.

  Non-delete operations always pass. For delete operations, the root schema must
  not declare persisted `:deleted_at` or `:archived_at` fields.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.fetch!(opts, name(), [:validate])

    with true <- CheckOptions.enabled?(check_opts),
         {:error, issue} <- issue_for(operation, query) do
      {:error, issue}
    else
      _ok -> :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp issue_for(:delete_all, query) do
    with {:ok, schema} <- Introspection.root_schema(query),
         soft_delete_fields = soft_delete_fields(schema),
         false <- Enum.empty?(soft_delete_fields) do
      {:error, issue(schema, soft_delete_fields)}
    else
      _not_applicable -> :ok
    end
  end

  defp issue_for(_operation, _query), do: :ok

  defp soft_delete_fields(schema) do
    schema_fields = Introspection.schema_fields(schema)

    Enum.filter(@soft_delete_fields, &MapSet.member?(schema_fields, &1))
  end

  @spec issue(module(), list(atom())) :: Issue.t()
  defp issue(schema, soft_delete_fields) do
    %Issue{
      check: __MODULE__,
      message: "expected delete_all on schema with soft-delete fields to use update_all instead",
      meta: %{
        operation: :delete_all,
        root_schema: schema,
        soft_delete_fields: soft_delete_fields
      }
    }
  end
end
