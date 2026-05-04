defmodule Bylaw.Db do
  @moduledoc """
  Validation entrypoint for database checks.

  Adapter modules usually provide the public entrypoint callers use directly.
  This module holds the shared check runner.
  """

  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @typedoc """
  A check module with optional check-specific options.
  """
  @type check_spec :: module() | {module(), keyword()}

  @doc """
  Runs `checks` against a non-empty list of targets.

  Checks run independently for each explicit target. The return shape matches
  individual checks: `:ok`, `{:error, issue}`, or `{:error, issues}`.
  """
  @spec validate(list(Target.t()), list(check_spec())) :: Check.result()
  def validate(targets, checks) when is_list(targets) and is_list(checks) do
    targets
    |> validate_targets!()
    |> Enum.flat_map(&target_issues(&1, checks))
    |> result()
  end

  def validate(_targets, checks) when not is_list(checks) do
    raise ArgumentError, "expected checks to be a list, got: #{inspect(checks)}"
  end

  def validate(targets, _checks) do
    raise ArgumentError, "expected database targets to be a list, got: #{inspect(targets)}"
  end

  defp target_issues(%Target{} = target, checks) do
    Enum.flat_map(checks, &check_issues(target, &1))
  end

  defp target_issues(target, _checks) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_targets!([]), do: raise(ArgumentError, "expected at least one database target")
  defp validate_targets!(targets), do: targets

  defp check_issues(target, check_spec) do
    {check, opts} = normalize_check!(check_spec)

    case check.validate(target, opts) do
      :ok -> []
      {:error, issues} when is_list(issues) -> issues
      {:error, %Issue{} = issue} -> [issue]
    end
  end

  defp normalize_check!({check, opts}) when is_atom(check) do
    if is_list(opts) and Keyword.keyword?(opts) do
      {check, opts}
    else
      raise ArgumentError, "expected check opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_check!(check) when is_atom(check), do: {check, []}

  defp normalize_check!(check) do
    raise ArgumentError, "expected a check module or {check, opts}, got: #{inspect(check)}"
  end

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
  defp result(issues), do: {:error, issues}
end
