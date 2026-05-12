defmodule Bylaw.HTML.Check.PreferLinkForNavigation do
  @moduledoc """
  Validates that rendered HTML uses links for durable navigation.

  This check is intentionally narrow. It only inspects rendered non-`a`
  elements with `phx-click` attributes and only flags JSON LiveView JS command
  sequences containing `navigate` or `patch`.

  ## Examples

  Bad:

      <button phx-click='[["navigate",{"href":"/settings","replace":false}]]'>
        Settings
      </button>

  Why this is bad:

  The button performs durable navigation, but browsers and assistive technology
  cannot treat it like a link. Users lose normal link affordances such as
  opening in a new tab, copying the target URL, and seeing a destination.

  Better:

      <a href="/settings">Settings</a>

  Why this is better:

  The destination is represented as a link in the rendered HTML.

  Bad:

      <div phx-click='[["patch",{"href":"/users","replace":false}]]'>Users</div>

  Why this is bad:

  A non-interactive element is handling navigation. It needs extra keyboard and
  accessibility work and still does not expose a durable destination.

  Better:

      <a href="/users" data-phx-link="patch" data-phx-link-state="push">Users</a>

  Why this is better:

  LiveView patch navigation is still rendered as an anchor with an `href`.

  ## Notes

  This check only detects JSON-encoded LiveView JS command sequences in
  `phx-click` attributes. It flags `navigate` and `patch` commands on rendered
  elements other than `<a>`.

  Non-navigation `phx-click` events are allowed:

      <button type="button" phx-click="save">Save</button>
      <button type="button" phx-click='[["push",{"event":"save"}]]'>Save</button>

  Malformed or non-JSON `phx-click` values are ignored because this check only
  validates command sequences it can identify.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.PreferLinkForNavigation

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.HTML`.
  See `Bylaw.HTML` for the full rendered HTML validation setup.
  """

  @behaviour Bylaw.HTML.Check

  alias Bylaw.HTML.Issue

  @navigation_ops ["navigate", "patch"]

  @doc """
  Implements the `Bylaw.HTML.Check` validation callback.
  """
  @impl Bylaw.HTML.Check
  @spec validate(Bylaw.HTML.Check.context()) :: Bylaw.HTML.Check.result()
  def validate(%{document: document}) do
    document
    |> LazyHTML.query("[phx-click]")
    |> Enum.flat_map(&issues_for_element/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp issues_for_element(element) do
    tag = element_tag(element)

    element
    |> phx_click_value()
    |> navigation_op()
    |> issue_list(tag, element)
  end

  defp element_tag(element) do
    element
    |> LazyHTML.tag()
    |> List.first()
  end

  defp phx_click_value(element) do
    element
    |> LazyHTML.attribute("phx-click")
    |> List.first()
  end

  defp navigation_op(nil), do: nil

  defp navigation_op(phx_click) do
    with {:ok, commands} <- Jason.decode(phx_click),
         true <- is_list(commands) do
      Enum.find_value(commands, &navigation_command/1)
    else
      _not_navigation -> nil
    end
  end

  defp navigation_command([operation | _rest]) when operation in @navigation_ops, do: operation
  defp navigation_command(_command), do: nil

  defp issue_list(_operation, "a", _element), do: []
  defp issue_list(_operation, nil, _element), do: []
  defp issue_list(nil, _tag, _element), do: []

  defp issue_list(operation, tag, element) do
    [
      %Issue{
        check: __MODULE__,
        message:
          "expected durable navigation to use <a>; found phx-click #{operation} on <#{tag}>",
        tag: tag,
        snippet: element_snippet(element)
      }
    ]
  end

  defp element_snippet(element) do
    LazyHTML.to_html(element)
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
