defmodule Bylaw.Ecto.Query.Issue do
  @moduledoc """
  Describes a query validation issue found by a check.
  """

  @type t :: %__MODULE__{
          check: module(),
          message: String.t(),
          meta: map()
        }

  defstruct check: nil,
            message: "",
            meta: %{}

  @doc """
  Formats a query issue for human-readable error output.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = issue) do
    base = "#{inspect(issue.check)}: #{issue.message}"

    if issue.meta == %{} do
      base
    else
      base <> " " <> inspect(issue.meta)
    end
  end

  @doc """
  Formats many query issues for human-readable error output.
  """
  @spec format_many(list(t())) :: String.t()
  def format_many(issues) when is_list(issues) do
    Enum.map_join(issues, "\n", &format/1)
  end
end
