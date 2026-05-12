defmodule Bylaw.HTML.Check.RequireLinkHref do
  @moduledoc """
  Validates that rendered anchor tags define an `href` attribute.

  This check inspects rendered `<a>` elements and flags anchors without `href`.
  Use a `<button>` for actions that do not navigate.

  Valid examples:

      <a href="/settings">Settings</a>
      <a href="">Current page</a>

  Invalid examples:

      <a>Settings</a>
      <a phx-click="save">Save</a>
  """

  @behaviour Bylaw.HTML.Check

  alias Bylaw.HTML.Issue

  @doc """
  Implements the `Bylaw.HTML.Check` validation callback.
  """
  @impl Bylaw.HTML.Check
  @spec validate(Bylaw.HTML.Check.context()) :: Bylaw.HTML.Check.result()
  def validate(%{document: document}) do
    document
    |> LazyHTML.query("a")
    |> Enum.filter(&missing_href?/1)
    |> Enum.map(&issue_for/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp missing_href?(element) do
    element
    |> LazyHTML.attribute("href")
    |> Enum.empty?()
  end

  defp issue_for(element) do
    %Issue{
      check: __MODULE__,
      message: "expected <a> to define href; use <button> for actions",
      tag: "a",
      snippet: LazyHTML.to_html(element)
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
