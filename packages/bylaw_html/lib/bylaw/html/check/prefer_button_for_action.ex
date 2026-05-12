defmodule Bylaw.HTML.Check.PreferButtonForAction do
  @moduledoc """
  Validates that rendered HTML uses buttons for non-navigation actions.

  This check inspects rendered `<a>` elements with `phx-click` and flags
  placeholder action hrefs. Use an anchor for durable navigation, and use a
  button for actions handled by events.

  Valid examples:

      <a href="/settings">Settings</a>
      <a href="/settings" phx-click="track">Settings</a>
      <button type="button" phx-click="save">Save</button>

  Invalid examples:

      <a href="#" phx-click="save">Save</a>
      <a href="" phx-click="open">Open</a>
      <a href="javascript:void(0)" phx-click="save">Save</a>
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
    |> LazyHTML.query("a[phx-click][href]")
    |> Enum.filter(&action_href?/1)
    |> Enum.map(&issue_for/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp action_href?(element) do
    element
    |> href_value()
    |> action_href_value?()
  end

  defp href_value(element) do
    element
    |> LazyHTML.attribute("href")
    |> List.first()
  end

  defp action_href_value?(nil), do: false

  defp action_href_value?(href) do
    href =
      href
      |> String.trim()
      |> String.downcase()

    href in ["", "#", "javascript:void(0)", "javascript:void(0);"]
  end

  defp issue_for(element) do
    %Issue{
      check: __MODULE__,
      message: "expected action links to use <button>; found <a> with phx-click and action href",
      tag: "a",
      snippet: LazyHTML.to_html(element)
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
