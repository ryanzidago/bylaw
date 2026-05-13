defmodule Bylaw.Ecto.Query do
  @moduledoc """
  Runs Ecto query checks from an explicit list of check specs.

  `Bylaw.Ecto.Query.validate/3` is the public entry point for end-user query
  validation. Use it from `c:Ecto.Repo.prepare_query/3` when you want repo-wide
  enforcement while keeping check selection explicit:

      @query_checks [
        Bylaw.Ecto.Query.Checks.RequiredOrder,
        {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
         rules: [fields: [:organization_id]]},
        {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
         rules: [
           [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]],
           [where: [tables: ["comments"]], fields: [:deleted_at]]
         ]}
      ]

      def prepare_query(operation, query, opts) do
        case Bylaw.Ecto.Query.validate(operation, query, @query_checks) do
          :ok -> {query, opts}
          {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
        end
      end

  A check spec is either a check module or `{check_module, opts}`. Each check
  module may appear at most once.

  > #### Warning {: .warning}
  >
  > `bylaw_ecto_query` inspects prepared `%Ecto.Query{}` structs. Ecto exposes
  > `Ecto.Query.t()`, but the internal shape of query expressions is not a
  > stable extension API. Review and run your enabled checks when upgrading
  > Ecto.

  ## Examples

  Zero-config checks stay as bare modules:

      @query_checks [
        Bylaw.Ecto.Query.Checks.RequiredOrder
      ]

  Configurable checks use `:rules` as their only public entry point. A single
  global rule can use the shorthand keyword form:

      @query_checks [
        {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
         rules: [fields: [:organization_id]]}
      ]

  Scoped rules use the list-of-rules form:

      @query_checks [
        {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
         rules: [
           [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]],
           [where: [tables: ["comments"]], fields: [:deleted_at]]
         ]}
      ]

  ## Rules DSL

  Every built-in check can be scoped with `rules:`. Scope is shared across
  checks; payload is check-specific. Use a bare module for global default
  behavior. Use `{Check, rules: [...]}` when the check should run only for
  matching queries.

  Shared scope keys are `where:` and `except:`. `where:` applies a rule when any
  matcher matches, and `except:` suppresses a rule that would otherwise match.
  Ecto query matchers use plural keys with list values: `ecto_schemas:`,
  `tables:`, `db_schemas:`, and `operations:`.

  Rule payload keys by check:

  | Check | Payload keys |
  | --- | --- |
  | `MandatoryWhereKeys` | `fields:`, optional `match:` |
  | `ExplicitVisibilityPredicates` | `fields:` |
  | `MandatoryJoinKeys` | `keys:`, optional `match:` |
  | `HalfOpenTemporalIntervals` | optional `fields:` |
  | `UtcDatetimeNaiveComparisons` | optional `fields:` |
  | all other built-in checks | none |

      iex> import Ecto.Query
      iex> query = from("posts", as: :post, limit: 1)
      iex> {:error, [issue]} =
      ...>   Bylaw.Ecto.Query.validate(:all, query, [
      ...>     Bylaw.Ecto.Query.Checks.RequiredOrder
      ...>   ])
      iex> issue.check
      Bylaw.Ecto.Query.Checks.RequiredOrder

      iex> Bylaw.Ecto.Query.validate(:all, :query, [])
      :ok
  """

  alias Bylaw.CheckRunner
  alias Bylaw.Ecto.Query.Check
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue

  @type check_spec :: module() | {module(), Check.opts()}
  @type checks :: list(check_spec())

  @doc """
  Runs the given query checks against a prepared Ecto query.

  Returns `:ok` when every enabled check passes. Returns `{:error, issues}`
  when one or more checks fail.

  `checks` accepts modules and `{module, opts}` tuples. Duplicate check modules
  raise `ArgumentError`. Bylaw does not read check lists from application
  config; callers pass checks explicitly.
  """
  @spec validate(Check.operation(), Check.query(), checks()) ::
          :ok | {:error, nonempty_list(Issue.t())}
  def validate(operation, query, checks) when is_list(checks) do
    checks
    |> normalize_checks!()
    |> Enum.flat_map(&issues_for_check(&1, operation, query))
    |> result()
  end

  def validate(_operation, _query, checks) do
    raise ArgumentError, "expected checks to be a list, got: #{inspect(checks)}"
  end

  defp normalize_checks!(checks) do
    checks
    |> Enum.reduce({MapSet.new(), []}, fn check_spec, {seen_checks, check_specs} ->
      {check, opts} = normalize_check_spec!(check_spec)
      seen_checks = put_unique_check!(seen_checks, check)

      {seen_checks, [{check, opts} | check_specs]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp put_unique_check!(seen_checks, check) do
    if MapSet.member?(seen_checks, check) do
      raise ArgumentError, "duplicate query check: #{inspect(check)}"
    end

    MapSet.put(seen_checks, check)
  end

  defp normalize_check_spec!(check) when is_atom(check) do
    ensure_check!(check)
    {check, []}
  end

  defp normalize_check_spec!({check, opts}) when is_atom(check) do
    ensure_check!(check)
    {check, CheckOptions.keyword_list!(opts, "check opts")}
  end

  defp normalize_check_spec!(check_spec) do
    raise ArgumentError,
          "expected check spec to be a module or {module, opts}, got: #{inspect(check_spec)}"
  end

  defp ensure_check!(check) do
    with {:module, ^check} <- Code.ensure_loaded(check),
         true <- function_exported?(check, :validate, 3) do
      :ok
    else
      _not_a_check ->
        raise ArgumentError, "expected #{inspect(check)} to be a query check module"
    end
  end

  defp issues_for_check({check, opts}, operation, query) do
    result = check.validate(operation, query, opts)

    apply(CheckRunner, :result!, [check, result, Issue, 3])
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
