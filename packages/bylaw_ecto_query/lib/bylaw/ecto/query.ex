defmodule Bylaw.Ecto.Query do
  @moduledoc """
  Runs Ecto query checks from an explicit list of check specs.

  `Bylaw.Ecto.Query.validate/3` and `Bylaw.Ecto.Query.validate/4` are the
  public entry points for end-user query validation. Use them from
  `c:Ecto.Repo.prepare_query/3` when you want repo-wide enforcement while
  keeping check selection explicit:

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
        case Bylaw.Ecto.Query.validate(
               operation,
               query,
               @query_checks,
               Keyword.get(opts, :bylaw, [])
             ) do
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

  ## Rules DSL

  Every check can be scoped with `:rules`. Rule scope is shared across checks;
  check-specific rule options stay specific to each check.

  A bare module applies that check globally with its defaults:

      @query_checks [
        Bylaw.Ecto.Query.Checks.RequiredOrder
      ]

  `{Check, rules: [...]}` runs the check only when at least one rule scope
  matches. A single global rule can use the shorthand keyword form:

      @query_checks [
        {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
         rules: [fields: [:organization_id]]}
      ]

  Scoped rules use the list-of-rules form. `:where` and `:except` are shared
  scope keys:

      @query_checks [
        {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
         rules: [
           [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]],
           [where: [tables: ["comments"]], fields: [:deleted_at]]
         ]}
      ]

  Matchers use plural keys with list values:

      rules: [
        where: [
          ecto_schemas: [Post],
          tables: ["posts"],
          db_schemas: ["public"],
          operations: [:all, :stream]
        ]
      ]

  Top-level `validate: false` is a check spec option that disables the whole
  check, especially when passed through call-site overrides. Rule-level
  `validate: false` disables only that rule. Checks with no check-specific rule
  options accept only `:where`, `:except`, and `validate: false` inside rules.
  Checks with required rule options validate those options only for matching
  rules.

  Each check module documents its own rule options and copyable rule examples.

  ## Call-Site Overrides

  Ecto passes repo call options to `c:Ecto.Repo.prepare_query/3`, so callers
  can pass per-call Bylaw options with `Repo.all(query, bylaw: ...)`.

  Bylaw does not read those options automatically. Apps explicitly opt in by
  passing `Keyword.get(opts, :bylaw, [])` to `Bylaw.Ecto.Query.validate/4`
  inside `prepare_query/3`:

      @query_checks [
        Bylaw.Ecto.Query.Checks.RequiredOrder,
        {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
         rules: [fields: [:organization_id]]}
      ]

      def prepare_query(operation, query, opts) do
        case Bylaw.Ecto.Query.validate(
               operation,
               query,
               @query_checks,
               Keyword.get(opts, :bylaw, [])
             ) do
          :ok -> {query, opts}
          {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
        end
      end

  Repo-wide check specs define defaults. Call-site `bylaw:` specs replace
  matching repo-wide specs and append new checks after the unchanged repo-wide
  checks. Passing `bylaw: false` disables all checks for that call.

      Repo.all(query, bylaw: false)

      Repo.all(query,
        bylaw: [
          {Bylaw.Ecto.Query.Checks.RequiredOrder, validate: false}
        ])

      Repo.all(query,
        bylaw: [
          {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
           rules: [fields: [:account_id]]}
        ])

      Repo.all(query,
        bylaw: [
          Bylaw.Ecto.Query.Checks.EmptyInPredicates
        ])

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

  @doc """
  Runs base query checks with explicit call-site Bylaw options.

  Pass the value from `Keyword.get(repo_opts, :bylaw, [])` as `bylaw_opts`.
  Bylaw does not read Ecto repo options automatically.

  An empty option list preserves the base checks. `false` disables all checks
  for the call site. A call-site check spec with the same module as a base spec
  replaces it entirely; a new check module is appended after the base checks
  that were not replaced.
  """
  @spec validate(Check.operation(), Check.query(), checks(), false | checks()) ::
          :ok | {:error, nonempty_list(Issue.t())}
  def validate(operation, query, base_checks, bylaw_opts) do
    checks = apply_opts!(base_checks, bylaw_opts)

    validate(operation, query, checks)
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

  defp apply_opts!(_base_checks, false), do: []

  defp apply_opts!(base_checks, call_site_checks)
       when is_list(base_checks) and is_list(call_site_checks) do
    base_checks = normalize_checks!(base_checks)
    call_site_checks = normalize_checks!(call_site_checks)

    call_site_checks_by_module = Map.new(call_site_checks, fn {check, opts} -> {check, opts} end)
    base_check_modules = MapSet.new(base_checks, fn {check, _opts} -> check end)

    replaced_base_checks =
      Enum.map(base_checks, fn {check, opts} ->
        {check, Map.get(call_site_checks_by_module, check, opts)}
      end)

    appended_call_site_checks =
      Enum.reject(call_site_checks, fn {check, _opts} ->
        MapSet.member?(base_check_modules, check)
      end)

    replaced_base_checks ++ appended_call_site_checks
  end

  defp apply_opts!(base_checks, _call_site_checks) when not is_list(base_checks) do
    raise ArgumentError, "expected checks to be a list, got: #{inspect(base_checks)}"
  end

  defp apply_opts!(_base_checks, call_site_checks) do
    raise ArgumentError,
          "expected call-site Bylaw opts to be false or a list, got: #{inspect(call_site_checks)}"
  end

  defp issues_for_check({check, opts}, operation, query) do
    result = check.validate(operation, query, opts)

    apply(CheckRunner, :result!, [check, result, Issue, 3])
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
