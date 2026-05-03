defmodule Bylaw.Ecto.Query do
  @moduledoc """
  Runs Ecto query checks from module-based check specs.

  Use this module from `c:Ecto.Repo.prepare_query/3` when you want Bylaw to own
  check orchestration while keeping check selection explicit:

      @bylaw [
        Bylaw.Ecto.Query.Checks.RequiredOrder,
        {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, keys: [:organisation_id]}
      ]

      def prepare_query(operation, query, opts) do
        checks = @bylaw ++ Keyword.get(opts, :bylaw, [])

        case Bylaw.Ecto.Query.validate(operation, query, checks) do
          :ok -> {query, opts}
          {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
        end
      end

  A check spec is either a check module or `{check_module, opts}`. When a module
  appears more than once, the later spec replaces the earlier spec's options
  without changing the original check order. This lets callers append query-level
  overrides to repo defaults.
  """

  alias Bylaw.Ecto.Query.Check
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue

  @type check_spec :: module() | {module(), Check.opts()}
  @type checks :: list(check_spec())

  @doc """
  Runs the configured query checks.

  Returns `:ok` when every enabled check passes. Returns `{:error, issues}`
  with a normalized issue list when one or more checks fail.

  `checks` accepts modules and `{module, opts}` tuples. Built-in checks treat
  `validate: false` as an escape hatch.
  """
  @spec validate(Check.operation(), Check.query(), checks()) :: :ok | {:error, list(Issue.t())}
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
    |> Enum.reduce({[], %{}}, fn check_spec, {check_order, check_specs} ->
      {check, opts} = normalize_check_spec!(check_spec)
      check_order = maybe_add_check(check_order, check_specs, check)

      {check_order, Map.put(check_specs, check, opts)}
    end)
    |> then(fn {check_order, check_specs} ->
      check_order
      |> Enum.reverse()
      |> Enum.map(&{&1, Map.fetch!(check_specs, &1)})
    end)
  end

  defp maybe_add_check(check_order, check_specs, check) do
    if Map.has_key?(check_specs, check) do
      check_order
    else
      [check | check_order]
    end
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
    case check.validate(operation, query, opts) do
      :ok ->
        []

      {:error, issue_or_issues} ->
        List.wrap(issue_or_issues)

      result ->
        raise ArgumentError,
              "expected #{inspect(check)}.validate/3 to return :ok or {:error, issue_or_issues}, got: #{inspect(result)}"
    end
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
