defmodule Bylaw.Ecto.Query.Checks.MandatoryJoinKeys do
  @moduledoc """
  Validates that explicit schema joins preserve configured mandatory keys.

  This check is intentionally narrow. It handles direct schema joins.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> join(:inner, [post: p], c in Comment,
        as: :comment,
        on: c.post_id == p.id
      )

  Why this is bad:

  If `:organization_id` is configured as mandatory, the join preserves the row
  relationship but not the tenant key. Bad or inconsistent foreign-key data can
  cross tenant boundaries.

  Better:

      from(Post, as: :post)
      |> join(:inner, [post: p], c in Comment,
        as: :comment,
        on:
          c.post_id == p.id and
            c.organization_id == p.organization_id
      )

  Why this is better:

  The join requires both the row relationship and the configured key to match.

  ## Notes

  This check only validates direct explicit schema joins and supported equality
  predicates in the join `on` expression. Association joins, subqueries,
  fragments, and schema-less joins are ignored.

  Association joins, subqueries, fragments, and schema-less joins are not
  validated by this check.

  Like Bylaw's other Ecto query checks, this reads Ecto query structs directly.
  Ecto treats those structs as opaque, so this check intentionally supports a
  small, tested subset of Ecto's query AST.

  ## Options

    * `:validate` - explicit `false` disables this check. It can be used in the
      repo-wide check list or in call-site overrides passed to
      `Bylaw.Ecto.Query.validate/4`.
    * `:rules` - optional rule keyword list or non-empty list of rule keyword
      lists. When omitted, top-level `:keys` and `:match` preserve the current
      global behavior for compatibility.
    * `:keys` - required non-empty list of field names when the check runs.
    * `:match` - `:any` or `:all`. Defaults to `:any`.

  This check requires `:keys`, so bare-module configuration is not valid.

  Run globally:

      {Bylaw.Ecto.Query.Checks.MandatoryJoinKeys,
       rules: [keys: [:organization_id]]}

  Run only for matching rule scopes:

      {Bylaw.Ecto.Query.Checks.MandatoryJoinKeys,
       rules: [
         [where: [ecto_schemas: [Post]], keys: [:organization_id]],
         [where: [tables: ["posts"]], keys: [:organization_id]]
       ]}

  Require every configured key instead of any one key:

      {Bylaw.Ecto.Query.Checks.MandatoryJoinKeys,
       rules: [keys: [:organization_id, :account_id], match: :all]}

  When a join schema does not contain any configured keys, that join is not
  applicable and the check returns no issue for it. For applicable joins, the
  check accepts direct equality predicates between the joined binding and
  another query binding in the join `on` expression.

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
  @type match :: :any | :all
  @typedoc false
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:keys, list(atom())}
            | {:match, match()}
          )
  @typedoc false
  @type opts :: check_opts()
  @typedoc false
  @type field_set :: list(atom())

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:keys, :match, :validate, :rules])

    if CheckOptions.enabled?(check_opts) do
      rules = RuleOptions.rules_or_default!(check_opts, :mandatory_join_keys, [:keys, :match])

      case issues(operation, query, rules) do
        [] -> :ok
        issues -> {:error, issues}
      end
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp rule_options!(opts) do
    %{
      keys: CheckOptions.fetch_non_empty_atoms!(opts, :keys),
      match: CheckOptions.match!(opts)
    }
  end

  defp issues(operation, query, rules) when is_map(query) do
    aliases = Introspection.aliases(query)
    matching_rules = RuleOptions.matching_rules(operation, query, rules, &rule_options!/1)

    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      Enum.flat_map(matching_rules, &issues_for_join(operation, join, join_index, aliases, &1))
    end)
  end

  defp issues(_operation, _query, _rules), do: []

  defp issues_for_join(operation, join, join_index, aliases, rule) do
    binding_index = join_index + 1

    with {:ok, schema} <- Introspection.explicit_join_schema(join),
         [_first_key | _remaining_keys] = applicable_keys <- applicable_keys(schema, rule.keys),
         found_keys <- join_keys(join, binding_index, aliases),
         missing_keys <- missing_keys(applicable_keys, found_keys, rule.match),
         false <- Enum.empty?(missing_keys) do
      [
        issue(
          operation,
          join_index,
          binding_index,
          schema,
          applicable_keys,
          found_keys,
          missing_keys,
          rule.match
        )
      ]
    else
      _other -> []
    end
  end

  defp applicable_keys(schema, keys) do
    schema_fields = Introspection.schema_fields(schema)
    Enum.filter(keys, &MapSet.member?(schema_fields, &1))
  end

  @spec join_keys(term(), pos_integer(), map()) :: field_set()
  defp join_keys(%{on: %{expr: expr}}, binding_index, aliases) do
    expr
    |> keys_in_join_expr(binding_index, aliases)
    |> Enum.uniq()
  end

  defp join_keys(_join, _binding_index, _aliases), do: []

  defp keys_in_join_expr({:and, _meta, [left, right]}, binding_index, aliases) do
    keys_in_join_expr(left, binding_index, aliases) ++
      keys_in_join_expr(right, binding_index, aliases)
  end

  defp keys_in_join_expr({:==, _meta, [left, right]}, binding_index, aliases) do
    with {:ok, {left_index, left_field}} <- Introspection.field(left, aliases),
         {:ok, {right_index, right_field}} <- Introspection.field(right, aliases),
         true <- left_field == right_field do
      cond do
        left_index == binding_index and right_index < binding_index ->
          [left_field]

        right_index == binding_index and left_index < binding_index ->
          [right_field]

        true ->
          []
      end
    else
      _other -> []
    end
  end

  defp keys_in_join_expr(_expr, _binding_index, _aliases), do: []

  @spec missing_keys(list(atom()), field_set(), match()) :: list(atom())
  defp missing_keys(keys, found_keys, :any) do
    if Enum.any?(keys, &Enum.member?(found_keys, &1)), do: [], else: keys
  end

  defp missing_keys(keys, found_keys, :all) do
    Enum.reject(keys, &Enum.member?(found_keys, &1))
  end

  @spec issue(
          Bylaw.Ecto.Query.Check.operation(),
          non_neg_integer(),
          pos_integer(),
          module(),
          list(atom()),
          field_set(),
          list(atom()),
          match()
        ) :: Issue.t()
  defp issue(operation, join_index, binding_index, schema, keys, found_keys, missing_keys, match) do
    %Issue{
      check: __MODULE__,
      message: message(schema, keys, missing_keys, match),
      meta: %{
        operation: operation,
        join_index: join_index,
        binding_index: binding_index,
        join_schema: schema,
        keys: keys,
        match: match,
        missing_keys: missing_keys,
        found_join_keys: Enum.sort(found_keys)
      }
    }
  end

  defp message(schema, keys, _missing_keys, :any) do
    "expected explicit join to #{inspect(schema)} to match at least one mandatory key with an earlier binding: #{format_keys(keys)}"
  end

  defp message(schema, _keys, missing_keys, :all) do
    "expected explicit join to #{inspect(schema)} to match all mandatory keys with an earlier binding; missing: #{format_keys(missing_keys)}"
  end

  defp format_keys(keys), do: Enum.map_join(keys, ", ", &inspect/1)
end
