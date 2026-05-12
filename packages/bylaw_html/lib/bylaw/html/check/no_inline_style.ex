defmodule Bylaw.HTML.Check.NoInlineStyle do
  @moduledoc """
  Validates that rendered elements do not define inline `style` attributes.

  This check inspects rendered HTML and flags any element with a `style`
  attribute. Prefer classes or attributes that keep styling in CSS.

  ## Examples

  Bad:

      <div style="display: none">Menu</div>

  Why this is bad:

  Inline styles make visual behavior harder to reuse, override, test, and audit.

  Better:

      <div class="hidden">Menu</div>

  Why this is better:

  The styling is represented by a reusable class instead of embedded in the
  rendered markup.

  Bad:

      <button style="">Save</button>

  Why this is bad:

  An empty inline style still creates a style hook in rendered HTML.

  Better:

      <button class="button">Save</button>

  Why this is better:

  The element keeps styling concerns out of inline attributes.

  ## Notes

  This check flags any rendered `style` attribute, including empty values. It
  does not inspect stylesheet content or judge whether a class name has a
  matching CSS rule.

  This check runs on rendered HTML, so dynamic `style` attributes are evaluated
  after rendering.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.NoInlineStyle

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
    |> LazyHTML.query("[style]")
    |> Enum.map(&issue_for/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp issue_for(element) do
    tag = element_tag(element)

    %Issue{
      check: __MODULE__,
      message: "expected <#{tag}> to avoid inline style attributes",
      tag: tag,
      snippet: LazyHTML.to_html(element)
    }
  end

  defp element_tag(element) do
    element
    |> LazyHTML.tag()
    |> List.first()
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
