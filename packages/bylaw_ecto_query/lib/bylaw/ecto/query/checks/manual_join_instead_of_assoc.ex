defmodule Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssoc do
  @moduledoc """
  Validates that manual joins use `assoc/2` when a root association exists.

  This check catches direct schema joins that spell out a relationship already
  declared on the query root schema.

  ## Examples

  When `Post` defines `has_many :comments, Comment`, a manual join repeats
  association metadata that Ecto already knows:

      # Bad: the association is reimplemented by hand.
      from post in Post,
        join: comment in Comment,
        on: comment.post_id == post.id

  Write the join with `assoc/2` instead:

      # Better: Ecto uses the association metadata.
      from post in Post,
        join: comment in assoc(post, :comments)

  Association joins let Ecto use the association metadata for foreign keys,
  through joins, preloads, and future schema changes. Manual joins are only
  rejected when the joined source is an Ecto schema module and the root schema
  defines an association whose related schema matches it.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  This check intentionally looks at associations defined on the root schema,
  because those are the associations that can be used as `assoc(root, name)` in
  the query. Reverse-only associations on the joined schema are ignored.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()
  @type association_index :: %{module() => list(atom())}

  @doc """
  Validates that manual joins use root schema associations when available.

  Queries without a schema root, joins that already use `assoc/2`, and joins
  whose source is not a direct schema module are ignored.
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

  defp validate_enabled(operation, query) do
    case issues(operation, query) do
      [] -> :ok
      issues -> {:error, issues}
    end
  end

  defp issues(operation, query) do
    query
    |> Introspection.query_branches()
    |> Enum.flat_map(&issues_for_branch(operation, &1))
    |> Enum.sort_by(&{Map.get(&1.meta, :combination_path, []), &1.meta.join_index})
  end

  defp issues_for_branch(operation, {branch_path, query}) do
    issues(operation, branch_path, query)
  end

  defp issues(operation, branch_path, query) when is_map(query) do
    with {:ok, root_schema} <- Introspection.root_schema(query),
         joins when is_list(joins) <- Map.get(query, :joins, []) do
      associations_by_schema = associations_by_related_schema(root_schema)

      joins
      |> Enum.with_index()
      |> Enum.flat_map(
        &join_issues(&1, operation, branch_path, root_schema, associations_by_schema)
      )
    else
      _other -> []
    end
  end

  defp issues(_operation, _branch_path, _query), do: []

  defp join_issues(
         {join, join_index},
         operation,
         branch_path,
         root_schema,
         associations_by_schema
       ) do
    case manual_join_associations(join, associations_by_schema) do
      {:ok, join_schema, associations} ->
        [issue(operation, branch_path, join, join_index, root_schema, join_schema, associations)]

      :skip ->
        []
    end
  end

  defp manual_join_associations(join, associations_by_schema) do
    with true <- manual_join?(join),
         {:ok, join_schema} <- Introspection.explicit_join_schema(join),
         {:ok, associations} <- Map.fetch(associations_by_schema, join_schema) do
      {:ok, join_schema, associations}
    else
      _other -> :skip
    end
  end

  defp manual_join?(%{assoc: nil}), do: true
  defp manual_join?(join) when is_map(join), do: not Map.has_key?(join, :assoc)
  defp manual_join?(_join), do: false

  @spec associations_by_related_schema(module()) :: association_index()
  defp associations_by_related_schema(root_schema) do
    root_schema
    |> schema_associations()
    |> Enum.flat_map(fn association ->
      case related_schema(root_schema, association) do
        {:ok, related_schema} -> [{related_schema, association}]
        :skip -> []
      end
    end)
    |> Enum.group_by(fn {related_schema, _association} -> related_schema end, fn
      {_related_schema, association} -> association
    end)
    |> Map.new(fn {related_schema, associations} ->
      {related_schema, Enum.sort(associations)}
    end)
  end

  defp schema_associations(schema) do
    schema.__schema__(:associations)
  end

  defp related_schema(schema, association) do
    case schema.__schema__(:association, association) do
      nil -> :skip
      reflection -> related_schema_from_reflection(schema, reflection)
    end
  rescue
    UndefinedFunctionError -> :skip
  end

  defp related_schema_from_reflection(schema, reflection) do
    if filtered_association?(reflection) do
      :skip
    else
      reflection_related_schema(schema, reflection)
    end
  end

  defp filtered_association?(reflection) do
    non_empty_filter?(reflection, :where) or non_empty_filter?(reflection, :join_where)
  end

  defp non_empty_filter?(reflection, key) do
    filter = Map.get(reflection, key, [])

    not Enum.empty?(filter)
  end

  defp reflection_related_schema(_schema, %{related: related_schema})
       when is_atom(related_schema) and not is_nil(related_schema) do
    if function_exported?(related_schema, :__schema__, 1) do
      {:ok, related_schema}
    else
      :skip
    end
  end

  defp reflection_related_schema(schema, %{through: through}) when is_list(through) do
    through_related_schema(schema, through)
  end

  defp reflection_related_schema(_schema, _reflection), do: :skip

  defp through_related_schema(schema, [association]) do
    related_schema(schema, association)
  end

  defp through_related_schema(schema, [association | rest]) do
    case related_schema(schema, association) do
      {:ok, next_schema} -> through_related_schema(next_schema, rest)
      :skip -> :skip
    end
  end

  defp through_related_schema(_schema, _through), do: :skip

  @spec issue(
          Bylaw.Ecto.Query.Check.operation(),
          Introspection.branch_path(),
          term(),
          non_neg_integer(),
          module(),
          module(),
          list(atom())
        ) :: Issue.t()
  defp issue(operation, branch_path, join, join_index, root_schema, join_schema, associations) do
    meta =
      Map.merge(
        %{
          operation: operation,
          join_index: join_index,
          binding_index: join_index + 1,
          join_qual: Map.get(join, :qual),
          join_source: Map.get(join, :source),
          root_schema: root_schema,
          join_schema: join_schema,
          associations: associations
        },
        Introspection.combination_path_meta(branch_path)
      )

    %Issue{
      check: __MODULE__,
      message: message(join_index, root_schema, join_schema, associations),
      meta: meta
    }
  end

  defp message(join_index, root_schema, join_schema, [association]) do
    "expected join #{join_index} to use assoc/2 for existing association #{inspect(association)} from #{inspect(root_schema)} to #{inspect(join_schema)}"
  end

  defp message(join_index, root_schema, join_schema, associations) do
    "expected join #{join_index} to use assoc/2 for one of existing associations #{format_associations(associations)} from #{inspect(root_schema)} to #{inspect(join_schema)}"
  end

  defp format_associations(associations) do
    Enum.map_join(associations, ", ", &inspect/1)
  end
end
