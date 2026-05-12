defmodule Bylaw.HTML.Check.RequireImageAlt do
  @moduledoc """
  Validates that rendered image tags define an `alt` attribute.

  This check inspects rendered `<img>` elements and flags images without `alt`.
  Use `alt=""` for decorative images.

  Valid examples:

      <img src="/logo.svg" alt="Company logo">
      <img src="/spacer.svg" alt="">

  Invalid examples:

      <img src="/logo.svg">
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
