defmodule Bylaw.HTML.Check.RequireImageAlt do
  @moduledoc """
  Validates that rendered image tags define an `alt` attribute.

  This check inspects rendered `<img>` elements and flags images without `alt`.
  Use `alt=""` for decorative images.

  ## Examples

  Bad:

      <img src="/logo.svg">

  Why this is bad:

  An image without `alt` has no explicit accessible text alternative. Screen
  readers may announce the file path or omit useful content.

  Better:

      <img src="/logo.svg" alt="Company logo">

  Why this is better:

  The image has an accessible text alternative.

  Bad:

      <img src="/spacer.svg">

  Why this is bad:

  Decorative images should be intentionally hidden from assistive technology
  rather than left ambiguous.

  Better:

      <img src="/spacer.svg" alt="">

  Why this is better:

  Empty `alt` communicates that the image is decorative.

  ## Notes

  The check only verifies that an `alt` attribute is present. It allows
  `alt=""` because empty alt text is the expected markup for decorative images.
  It does not judge whether non-empty alt text is descriptive enough.

  This check runs on rendered HTML, so dynamic `alt` attributes are evaluated
  after rendering.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.RequireImageAlt

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
    |> LazyHTML.query("img")
    |> Enum.filter(&missing_alt?/1)
    |> Enum.map(&issue_for/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp missing_alt?(element) do
    element
    |> LazyHTML.attribute("alt")
    |> Enum.empty?()
  end

  defp issue_for(element) do
    %Issue{
      check: __MODULE__,
      message: ~s(expected <img> to define alt; use alt="" for decorative images),
      tag: "img",
      snippet: LazyHTML.to_html(element)
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
