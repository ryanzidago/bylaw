defmodule Bylaw.CheckRunner do
  @moduledoc false

  @doc false
  @spec result!(module(), term(), module(), pos_integer()) :: list(struct())
  def result!(_check, :ok, _issue_module, _arity), do: []

  def result!(check, {:error, issues} = result, issue_module, arity) when is_list(issues) do
    if Enum.any?(issues) and Enum.all?(issues, &issue?(&1, issue_module)) do
      issues
    else
      invalid_result!(check, result, arity)
    end
  end

  def result!(check, result, _issue_module, arity) do
    invalid_result!(check, result, arity)
  end

  defp issue?(%{__struct__: issue_module}, issue_module), do: true
  defp issue?(_issue, _issue_module), do: false

  defp invalid_result!(check, result, arity) do
    raise ArgumentError,
          "expected #{inspect(check)}.validate/#{arity} to return :ok or {:error, non_empty_issue_list}, got: #{inspect(result)}"
  end
end
