defmodule Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinct do
  @moduledoc """
  Warns when a root-row query joins many associations without obvious deduplication.

  Joining a `has_many` or `many_to_many` association multiplies the parent row
  once for every matching child row. When the query still returns root structs,
  that multiplication is usually accidental:

      from post in Post,
        join: comment in assoc(post, :comments),
        where: comment.status == ^:published

  If one post has three published comments, the database returns three rows for
  that post and Ecto maps them back to three identical root structs. Prefer
  `distinct`, `group_by`, or an `exists` predicate when the join is only a
  filter:

      from post in Post,
        join: comment in assoc(post, :comments),
        where: comment.status == ^:published,
        distinct: post.id

      @bylaw [
        has_many_join_without_distinct: [
          validate: true
        ]
      ]

      def prepare_query(operation, query, opts) do
        bylaw_opts =
          Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
            Keyword.merge(default, override)
          end)

        case Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinct.validate(
               operation,
               query,
               bylaw_opts
             ) do
          :ok -> {query, opts}
          {:error, issue} -> raise inspect(issue)
        end
      end

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [has_many_join_without_distinct: [validate: false]])

  Supported options:

      [
        has_many_join_without_distinct: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  This is intentionally a small educational check, not a full SQL row-stability
  analyzer. It only inspects the top-level query for root-row read operations,
  association joins built with `assoc/2`, and associations whose reflection has
  `cardinality: :many`. It reports only implicit root selects and explicit
  `select: root` queries. Queries with `distinct`, `group_by`, preloads,
  combination branches, source subqueries, CTE row sources, or other explicit
  result shapes are left alone.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @root_row_read_operations [:all, :stream]

  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()
  @type schemas_by_binding :: %{optional(non_neg_integer()) => module()}
  @type many_join :: %{
          association: atom(),
          binding_index: pos_integer(),
          join_index: non_neg_integer(),
          join_qual: atom() | nil,
          join_schema: module() | nil,
          owner_binding_index: non_neg_integer(),
          owner_schema: module()
        }

  @doc """
  Validates that top-level root-row reads do not directly join many associations.

  Queries outside the supported educational scope return `:ok`.
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
    if unsupported_scope?(operation, query) or not root_selecting_without_deduplication?(query) do
      []
    else
      query
      |> many_association_joins()
      |> Enum.map(&issue(operation, &1))
      |> Enum.sort_by(& &1.meta.join_index)
    end
  end

  defp unsupported_scope?(operation, query) do
    operation not in @root_row_read_operations or
      not is_map(query) or
      combination_query?(query) or
      not root_schema_source?(query)
  end

  defp combination_query?(%{combinations: combinations}) when is_list(combinations),
    do: Enum.any?(combinations)

  defp combination_query?(_query), do: false

  defp root_schema_source?(query) do
    match?({:ok, _schema}, Introspection.root_schema(query))
  end

  defp root_selecting_without_deduplication?(query) do
    root_select?(query) and
      not distinct?(query) and
      not grouped?(query) and
      not preloaded?(query)
  end

  defp root_select?(%{select: nil}), do: true
  defp root_select?(%{select: %{expr: {:&, _meta, [0]}}}), do: true
  defp root_select?(_query), do: false

  defp distinct?(%{distinct: nil}), do: false
  defp distinct?(%{distinct: %{expr: expr}}), do: expression_present?(expr)
  defp distinct?(%{distinct: _distinct}), do: true
  defp distinct?(_query), do: false

  defp grouped?(%{group_bys: group_bys}) when is_list(group_bys) do
    Enum.any?(group_bys, fn
      %{expr: expr} -> expression_present?(expr)
      _group_by -> false
    end)
  end

  defp grouped?(_query), do: false

  defp preloaded?(query) do
    query
    |> preload_entries()
    |> Enum.any?()
  end

  defp preload_entries(query), do: Map.get(query, :preloads, []) ++ Map.get(query, :assocs, [])

  defp expression_present?(nil), do: false
  defp expression_present?([]), do: false
  defp expression_present?(false), do: false
  defp expression_present?(_expr), do: true

  @spec many_association_joins(term()) :: list(many_join())
  defp many_association_joins(query) do
    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.reduce({root_schemas(query), []}, fn
      {join, join_index}, {schemas, many_joins} when is_map(join) ->
        binding_index = join_index + 1
        {schemas, association} = put_join_schema(schemas, join, binding_index)

        if many_association?(association) do
          {schemas, [many_join(join, join_index, binding_index, association) | many_joins]}
        else
          {schemas, many_joins}
        end

      {_join, _join_index}, state ->
        state
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp root_schemas(query) do
    case Introspection.root_schema(query) do
      {:ok, schema} -> %{0 => schema}
      :unknown -> %{}
    end
  end

  @spec put_join_schema(schemas_by_binding(), term(), pos_integer()) ::
          {schemas_by_binding(), map() | nil}
  defp put_join_schema(schemas, join, binding_index) do
    case association(join, schemas) do
      {:ok, association} ->
        {put_related_schema(schemas, binding_index, association), association}

      :skip ->
        {put_explicit_join_schema(schemas, join, binding_index), nil}
    end
  end

  defp association(%{assoc: {owner_binding_index, association_name}}, schemas)
       when is_integer(owner_binding_index) and owner_binding_index >= 0 and
              is_atom(association_name) do
    with {:ok, owner_schema} <- Map.fetch(schemas, owner_binding_index),
         {:ok, reflection} <- schema_association(owner_schema, association_name) do
      {:ok,
       %{
         association: association_name,
         owner_binding_index: owner_binding_index,
         owner_schema: owner_schema,
         reflection: reflection
       }}
    else
      _other -> :skip
    end
  rescue
    UndefinedFunctionError -> :skip
  end

  defp association(_join, _schemas), do: :skip

  defp schema_association(schema, association_name) do
    case schema.__schema__(:association, association_name) do
      nil -> :skip
      reflection -> {:ok, reflection}
    end
  end

  defp put_related_schema(schemas, binding_index, %{reflection: reflection}) do
    case related_schema(reflection) do
      {:ok, schema} -> Map.put(schemas, binding_index, schema)
      :skip -> schemas
    end
  end

  defp put_explicit_join_schema(schemas, join, binding_index) do
    case Introspection.explicit_join_schema(join) do
      {:ok, schema} -> Map.put(schemas, binding_index, schema)
      :skip -> schemas
    end
  end

  defp many_association?(%{reflection: %{cardinality: :many}}), do: true
  defp many_association?(_association), do: false

  defp many_join(join, join_index, binding_index, association) do
    %{
      association: association.association,
      binding_index: binding_index,
      join_index: join_index,
      join_qual: Map.get(join, :qual),
      join_schema: join_schema(association.reflection),
      owner_binding_index: association.owner_binding_index,
      owner_schema: association.owner_schema
    }
  end

  defp join_schema(reflection) do
    case related_schema(reflection) do
      {:ok, schema} -> schema
      :skip -> nil
    end
  end

  defp related_schema(%{related: schema}) when is_atom(schema) and not is_nil(schema) do
    if function_exported?(schema, :__schema__, 1) do
      {:ok, schema}
    else
      :skip
    end
  end

  defp related_schema(_reflection), do: :skip

  @spec issue(Bylaw.Ecto.Query.Check.operation(), many_join()) :: Issue.t()
  defp issue(operation, many_join) do
    %Issue{
      check: __MODULE__,
      message: message(many_join),
      meta: %{
        operation: operation,
        association: many_join.association,
        join_index: many_join.join_index,
        binding_index: many_join.binding_index,
        join_qual: many_join.join_qual,
        join_schema: many_join.join_schema,
        owner_binding_index: many_join.owner_binding_index,
        owner_schema: many_join.owner_schema
      }
    }
  end

  defp message(many_join) do
    "expected root-selecting query with many association join #{inspect(many_join.association)} to include distinct or group_by"
  end
end
