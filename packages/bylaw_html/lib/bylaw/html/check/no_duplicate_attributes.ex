defmodule Bylaw.HTML.Check.NoDuplicateAttributes do
  @moduledoc """
  Validates that rendered elements do not define the same attribute more than once.

  This check parses the original rendered HTML string with Floki because the
  normal `LazyHTML` document discards duplicate attributes while building a
  queryable document tree.

  ## Examples

  Bad:

      <div id="primary" id="secondary">Content</div>

  Why this is bad:

  Duplicate attributes are invalid HTML. Browsers and parsers keep one value and
  ignore the other, which can hide bugs in rendered output.

  Better:

      <div id="primary">Content</div>

  Why this is better:

  The element has one clear value for each attribute.

  Bad:

      <button class="primary" CLASS="secondary">Save</button>

  Why this is bad:

  HTML attribute names are case-insensitive, so these are duplicate attributes.

  Better:

      <button class="primary secondary">Save</button>

  Why this is better:

  The element expresses both classes through one `class` attribute.

  ## Notes

  This check reports duplicate attributes found in rendered elements. It uses
  Floki for this specific check so Bylaw does not own custom HTML tokenization
  logic for duplicate-sensitive parsing.

  This check runs on rendered HTML, so dynamic attributes are evaluated after
  rendering.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.NoDuplicateAttributes

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
  def validate(%{html: html}) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} ->
        nodes
        |> Enum.flat_map(&issues_for_node/1)
        |> result()

      {:error, _reason} ->
        :ok
    end
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with rendered HTML, got: #{inspect(context)}"
  end

  defp issues_for_node({tag, attrs, children} = node)
       when is_binary(tag) and is_list(attrs) and is_list(children) do
    attr_issues =
      attrs
      |> duplicate_names()
      |> Enum.map(&issue_for(tag, &1, node))

    child_issues = Enum.flat_map(children, &issues_for_node/1)

    attr_issues ++ child_issues
  end

  defp issues_for_node(_node), do: []

  defp duplicate_names(attrs) do
    attrs
    |> Enum.map(fn {name, _value} -> name end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> Enum.sort()
  end

  defp issue_for(tag, attr, node) do
    %Issue{
      check: __MODULE__,
      message: "expected <#{tag}> to define #{attr} only once",
      tag: tag,
      snippet: Floki.raw_html(node)
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
