defmodule Bylaw.Ecto.Query.Issue do
  @moduledoc """
  Describes a query validation issue found by a check.
  """

  @type t :: %__MODULE__{
          check: module(),
          message: String.t(),
          meta: map()
        }

  @type format_opt :: {:meta, boolean()}
  @type format_opts :: list(format_opt())

  defstruct check: nil,
            message: "",
            meta: %{}

  @doc """
  Formats a query issue for human-readable error output.

  Metadata is omitted by default because issue messages are meant for humans and
  often already contain the actionable details. Pass `meta: true` to include the
  structured metadata for debugging.

  ## Examples

      iex> issue = %Bylaw.Ecto.Query.Issue{
      ...>   check: MyApp.RequiredOrder,
      ...>   message: "queries with limit require order_by",
      ...>   meta: %{operation: :all}
      ...> }
      iex> Bylaw.Ecto.Query.Issue.format(issue)
      "MyApp.RequiredOrder: queries with limit require order_by"

      iex> issue = %Bylaw.Ecto.Query.Issue{
      ...>   check: MyApp.RequiredOrder,
      ...>   message: "queries with limit require order_by",
      ...>   meta: %{operation: :all}
      ...> }
      iex> Bylaw.Ecto.Query.Issue.format(issue, meta: true)
      "MyApp.RequiredOrder: queries with limit require order_by %{operation: :all}"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = issue), do: format(issue, [])

  @doc """
  Formats a query issue for human-readable error output.
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
  Formats many query issues for human-readable error output.

  ## Examples

      iex> issues = [
      ...>   %Bylaw.Ecto.Query.Issue{check: MyApp.RequiredOrder, message: "missing order"},
      ...>   %Bylaw.Ecto.Query.Issue{check: MyApp.EmptyInPredicates, message: "empty in predicate"}
      ...> ]
      iex> Bylaw.Ecto.Query.Issue.format_many(issues)
      "MyApp.RequiredOrder: missing order\\nMyApp.EmptyInPredicates: empty in predicate"
  """
  @spec format_many(list(t())) :: String.t()
  def format_many(issues) when is_list(issues), do: format_many(issues, [])

  @doc """
  Formats many query issues for human-readable error output.
  """
  @spec format_many(list(t()), format_opts()) :: String.t()
  def format_many(issues, opts) when is_list(issues) and is_list(opts) do
    Enum.map_join(issues, "\n", &format(&1, opts))
  end
end
