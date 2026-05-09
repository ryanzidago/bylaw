defmodule Bylaw.Db.Issue do
  @moduledoc """
  Issue returned by a failed database validation check.
  """

  alias Bylaw.Db.Target

  @typedoc """
  A database validation issue.

  `check` identifies the check module that produced the issue, `message` is the
  human-readable failure text, `target` is the target that failed when available,
  and `meta` holds structured adapter- or check-specific details.
  """
  @type t :: %__MODULE__{
          check: module(),
          message: String.t(),
          target: Target.t() | nil,
          meta: map()
        }

  @typedoc """
  Formatting option.
  """
  @type format_opt :: {:meta, boolean()}

  @typedoc """
  Formatting options.
  """
  @type format_opts :: list(format_opt())

  defstruct check: nil,
            message: "",
            target: nil,
            meta: %{}

  @doc """
  Formats a database issue for human-readable error output.

  Metadata is omitted by default because issue messages are meant for humans and
  often already contain the actionable details. Pass `meta: true` to include the
  structured metadata for debugging.

  ## Examples

      iex> issue = %Bylaw.Db.Issue{
      ...>   check: MyApp.RequiredColumns,
      ...>   message: "users.email is nullable",
      ...>   meta: %{table: :users}
      ...> }
      iex> Bylaw.Db.Issue.format(issue)
      "MyApp.RequiredColumns: users.email is nullable"

      iex> issue = %Bylaw.Db.Issue{
      ...>   check: MyApp.RequiredColumns,
      ...>   message: "users.email is nullable",
      ...>   meta: %{table: :users}
      ...> }
      iex> Bylaw.Db.Issue.format(issue, meta: true)
      "MyApp.RequiredColumns: users.email is nullable %{table: :users}"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = issue), do: format(issue, [])

  @doc """
  Formats a database issue for human-readable error output.
  """
  @spec format(t(), format_opts()) :: String.t()
  def format(%__MODULE__{} = issue, opts) when is_list(opts) do
    base = "#{inspect(issue.check)}: #{issue.message}"

    if Keyword.get(opts, :meta, false) and issue.meta != %{} do
      base <> " " <> inspect(issue.meta)
    else
      base
    end
  end

  @doc """
  Formats many database issues for human-readable error output.

  ## Examples

      iex> issues = [
      ...>   %Bylaw.Db.Issue{check: MyApp.RequiredColumns, message: "users.email is nullable"},
      ...>   %Bylaw.Db.Issue{check: MyApp.RequiredColumns, message: "posts.account_id is nullable"}
      ...> ]
      iex> Bylaw.Db.Issue.format_many(issues)
      "MyApp.RequiredColumns: users.email is nullable\\nMyApp.RequiredColumns: posts.account_id is nullable"
  """
  @spec format_many(list(t())) :: String.t()
  def format_many(issues) when is_list(issues), do: format_many(issues, [])

  @doc """
  Formats many database issues for human-readable error output.
  """
  @spec format_many(list(t()), format_opts()) :: String.t()
  def format_many(issues, opts) when is_list(issues) and is_list(opts) do
    Enum.map_join(issues, "\n", &format(&1, opts))
  end
end
