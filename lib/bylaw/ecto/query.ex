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
  appears more than once, the later spec replaces the earlier spec, which lets
  callers append query-level overrides to repo defaults.
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
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {check_spec, index}, check_specs ->
      {check, opts} = normalize_check_spec!(check_spec)
      Map.put(check_specs, check, {index, check, opts})
    end)
    |> Map.values()
    |> Enum.sort_by(fn {index, _check, _opts} -> index end)
    |> Enum.map(fn {_index, check, opts} -> {check, opts} end)
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
