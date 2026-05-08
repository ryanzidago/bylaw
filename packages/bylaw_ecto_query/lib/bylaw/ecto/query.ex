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
        case Bylaw.Ecto.Query.validate(operation, query, @bylaw) do
          :ok -> {query, opts}
          {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
        end
      end

  A check spec is either a check module or `{check_module, opts}`. Each check
  module may appear at most once.
  """

  alias Bylaw.CheckRunner
  alias Bylaw.Ecto.Query.Check
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Issue

  @type check_spec :: module() | {module(), Check.opts()}
  @type checks :: list(check_spec())

  @doc """
  Runs the configured query checks.

  Returns `:ok` when every enabled check passes. Returns `{:error, issues}`
  when one or more checks fail.

  `checks` accepts modules and `{module, opts}` tuples. Duplicate check modules
  raise `ArgumentError`.
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
