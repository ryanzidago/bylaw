defmodule Bylaw.HTML.Check.RequireButtonType do
  @moduledoc """
  Validates that rendered button tags define a valid `type` attribute.

  This check inspects rendered `<button>` elements and flags buttons without a
  `type` attribute, or with a `type` value other than `button`, `submit`, or
  `reset`.

  ## Examples

  Bad:

      <button phx-click="save">Save</button>

  Why this is bad:

  Browsers default `<button>` elements to submit buttons, which can submit an
  enclosing form when the button was meant to run a local action.

  Better:

      <button type="button" phx-click="save">Save</button>

  Why this is better:

  The button behavior is explicit and does not depend on the browser default.

  Bad:

      <button type="save">Save</button>

  Why this is bad:

  Invalid button types are treated inconsistently by readers and tools.

  Better:

      <button type="submit">Save</button>

  Why this is better:

  The rendered markup uses one of the button types recognized by browsers.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.RequireButtonType

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.HTML`.
  See `Bylaw.HTML` for the full rendered HTML validation setup.
  """

  @behaviour Bylaw.HTML.Check

  alias Bylaw.HTML.Issue

  @valid_types ["button", "reset", "submit"]

  @doc """
  Implements the `Bylaw.HTML.Check` validation callback.
  """
  @impl Bylaw.HTML.Check
  @spec validate(Bylaw.HTML.Check.context()) :: Bylaw.HTML.Check.result()
  def validate(%{document: document}) do
    document
    |> LazyHTML.query("button")
    |> Enum.filter(&invalid_type?/1)
    |> Enum.map(&issue_for/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp invalid_type?(element) do
    element
    |> type_value()
    |> valid_type?()
    |> Kernel.not()
  end

  defp type_value(element) do
    element
    |> LazyHTML.attribute("type")
    |> List.first()
  end

  defp valid_type?(nil), do: false

  defp valid_type?(type) do
    normalized_type =
      type
      |> String.trim()
      |> String.downcase()

    normalized_type in @valid_types
  end

  defp issue_for(element) do
    %Issue{
      check: __MODULE__,
      message: "expected <button> to define a valid type attribute",
      tag: "button",
      snippet: LazyHTML.to_html(element)
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
