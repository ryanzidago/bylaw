defmodule Bylaw.HTML.Check.PreferLinkForNavigation do
  @moduledoc """
  Validates that rendered HTML uses links for durable navigation.

  This check is intentionally narrow. It only inspects rendered non-`a`
  elements with `phx-click` attributes and only flags JSON LiveView JS command
  sequences containing `navigate` or `patch`.

  Valid examples:

      <a href="/settings">Settings</a>
      <a href="/users" data-phx-link="patch" data-phx-link-state="push">Users</a>
      <button phx-click="save">Save</button>
      <button phx-click='[["push",{"event":"save"}]]'>Save</button>

  Invalid examples:

      <button phx-click='[["navigate",{"href":"/settings","replace":false}]]'>Settings</button>
      <div phx-click='[["patch",{"href":"/users","replace":false}]]'>Users</div>
      <span phx-click='[["push",{"event":"track"}],["navigate",{"href":"/reports","replace":false}]]'>Reports</span>
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
