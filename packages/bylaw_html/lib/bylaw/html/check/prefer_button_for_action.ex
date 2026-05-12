defmodule Bylaw.HTML.Check.PreferButtonForAction do
  @moduledoc """
  Validates that rendered HTML uses buttons for non-navigation actions.

  This check inspects rendered `<a>` elements with `phx-click` and flags
  placeholder action hrefs. Use an anchor for durable navigation, and use a
  button for actions handled by events.

  ## Examples

  Bad:

      <a href="#" phx-click="save">Save</a>

  Why this is bad:

  The element looks like a link, but the placeholder `href` has no durable
  destination. The real behavior is the event action attached to `phx-click`.

  Better:

      <button type="button" phx-click="save">Save</button>

  Why this is better:

  A button communicates that the element performs an action instead of
  navigating to another resource.

  Bad:

      <a href="javascript:void(0)" phx-click="open">Open</a>

  Why this is bad:

  A JavaScript placeholder suppresses normal link behavior and makes the anchor
  an action control.

  Better:

      <button type="button" phx-click="open">Open</button>

  Why this is better:

  The browser exposes the element as a control without pretending there is a
  navigable URL.

  ## Notes

  This check only flags rendered anchors that have both `phx-click` and a
  placeholder action href. It allows real navigation anchors, including anchors
  that also use `phx-click` for secondary behavior such as analytics:

      <a href="/settings" phx-click="track">Settings</a>

  It also allows fragment links without `phx-click`, such as
  `<a href="#details">Details</a>`.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.PreferButtonForAction

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.HTML`.
  See `Bylaw.HTML` for the full rendered HTML validation setup.
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
