defmodule Bylaw.HTML.Check.RequireLinkHref do
  @moduledoc """
  Validates that rendered anchor tags define an `href` attribute.

  This check inspects rendered `<a>` elements and flags anchors without `href`.
  Use a `<button>` for actions that do not navigate.

  ## Examples

  Bad:

      <a>Settings</a>

  Why this is bad:

  An anchor without `href` is not durable navigation. It is less predictable for
  keyboard users, assistive technology, browser affordances, and link behavior
  such as opening in a new tab or copying the target URL.

  Better:

      <a href="/settings">Settings</a>

  Why this is better:

  The element exposes a real destination, so it behaves like a browser link.

  Bad:

      <a phx-click="save">Save</a>

  Why this is bad:

  A click-only anchor is acting as an event control, not navigation.

  Better:

      <button type="button" phx-click="save">Save</button>

  Why this is better:

  A button communicates that the element performs an action.

  ## Notes

  The check only verifies that an `href` attribute is present. It allows
  `href=""` and `href="#"`; use `Bylaw.HTML.Check.PreferButtonForAction` to
  flag rendered action links that combine `phx-click` with placeholder hrefs.

  This check runs on rendered HTML, so dynamic attributes are evaluated after
  rendering. It does not report the source component or template that produced
  an anchor.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.RequireLinkHref

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
