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
  Runs `checks` against one target or a list of targets.

  Checks run independently for each explicit target. The return shape matches
  individual checks: `:ok`, `{:error, issue}`, or `{:error, issues}`.
  """
  @spec validate(Target.t() | list(Target.t()), list(check_spec())) :: Check.result()
  def validate(target_or_targets, checks) when is_list(checks) do
    target_or_targets
    |> targets!()
    |> Enum.flat_map(&target_issues(&1, checks))
    |> result()
  end

  defp target_issues(%Target{} = target, checks) do
    Enum.flat_map(checks, &check_issues(target, &1))
  end

  defp target_issues(target, _checks) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp targets!(%Target{} = target), do: [target]
  defp targets!(targets) when is_list(targets), do: targets

  defp targets!(target) do
    raise ArgumentError, "expected a database target or list of targets, got: #{inspect(target)}"
  end

  defp check_issues(target, check_spec) do
    {check, opts} = normalize_check!(check_spec)

    target
    |> check.validate(opts)
    |> issues()
  end

  defp normalize_check!({check, opts}) when is_atom(check) and is_list(opts), do: {check, opts}
  defp normalize_check!(check) when is_atom(check), do: {check, []}

  defp normalize_check!(check) do
    raise ArgumentError, "expected a check module or {check, opts}, got: #{inspect(check)}"
  end

  defp issues(:ok), do: []
  defp issues({:error, issues}) when is_list(issues), do: issues
  defp issues({:error, %Issue{} = issue}), do: [issue]

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
  defp result(issues), do: {:error, issues}
end
