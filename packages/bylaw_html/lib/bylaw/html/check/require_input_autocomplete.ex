defmodule Bylaw.HTML.Check.RequireInputAutocomplete do
  @moduledoc """
  Validates that rendered input fields define a non-blank `autocomplete` attribute.

  This check inspects rendered `<input>` elements that accept user-entered
  values and flags fields without an explicit autocomplete purpose. Use a
  specific autocomplete token where possible, or `autocomplete="off"` when a
  field intentionally should not be autofilled.

  ## Examples

  Bad:

      <input type="email" name="user[email]">

  Why this is bad:

  The browser and assistive technology cannot identify the expected input
  purpose from the rendered markup.

  Better:

      <input type="email" name="user[email]" autocomplete="email">

  Why this is better:

  The field exposes its input purpose in a machine-readable way.

  Bad:

      <input name="search" autocomplete="">

  Why this is bad:

  A blank autocomplete value is equivalent to leaving the purpose unspecified.

  Better:

      <input name="search" autocomplete="off">

  Why this is better:

  The rendered markup documents that autocomplete was considered and disabled
  intentionally.

  ## Notes

  This check ignores input controls where autocomplete is not meaningful:
  `button`, `checkbox`, `file`, `hidden`, `image`, `radio`, `reset`, and
  `submit`. Inputs without a `type` attribute are treated as text inputs.

  The check only verifies that a non-blank `autocomplete` value is present. It
  does not validate autocomplete token grammar or judge whether the chosen token
  matches the field's semantic purpose.

  This check runs on rendered HTML, so dynamic `autocomplete` attributes are
  evaluated after rendering.

  ## Options

  This check has no check-specific options. Add the module directly to the
  explicit checks list:

      Bylaw.HTML.Check.RequireInputAutocomplete

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.HTML`.
  See `Bylaw.HTML` for the full rendered HTML validation setup.
  """

  @behaviour Bylaw.HTML.Check

  alias Bylaw.HTML.Issue

  @ignored_input_types ~w(button checkbox file hidden image radio reset submit)

  @doc """
  Implements the `Bylaw.HTML.Check` validation callback.
  """
  @impl Bylaw.HTML.Check
  @spec validate(Bylaw.HTML.Check.context()) :: Bylaw.HTML.Check.result()
  def validate(%{document: document}) do
    document
    |> LazyHTML.query("input")
    |> Enum.reject(&ignored_input?/1)
    |> Enum.filter(&missing_autocomplete?/1)
    |> Enum.map(&issue_for/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with a parsed document, got: #{inspect(context)}"
  end

  defp ignored_input?(element) do
    input_type = element |> input_type() |> String.downcase()

    input_type in @ignored_input_types
  end

  defp input_type(element) do
    element
    |> LazyHTML.attribute("type")
    |> List.first()
    |> case do
      nil -> "text"
      type -> String.trim(type)
    end
  end

  defp missing_autocomplete?(element) do
    element
    |> autocomplete_value()
    |> blank?()
  end

  defp autocomplete_value(element) do
    element
    |> LazyHTML.attribute("autocomplete")
    |> List.first()
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(value) == ""

  defp issue_for(element) do
    %Issue{
      check: __MODULE__,
      message: "expected <input> to define a non-blank autocomplete attribute",
      tag: "input",
      snippet: LazyHTML.to_html(element)
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
