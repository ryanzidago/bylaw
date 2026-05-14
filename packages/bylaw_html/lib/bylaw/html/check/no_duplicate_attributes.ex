defmodule Bylaw.HTML.Check.NoDuplicateAttributes do
  @moduledoc """
  Validates that rendered elements do not define the same attribute more than once.

  This check inspects the original rendered HTML string because HTML parsers can
  discard duplicate attributes while building a document tree.

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

  This check reports duplicate attributes found in rendered start tags. It
  ignores closing tags, comments, declarations, and processing instructions.

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
    html
    |> start_tags()
    |> Enum.flat_map(&issues_for_tag/1)
    |> result()
  end

  def validate(context) do
    raise ArgumentError,
          "expected context to be a map with rendered HTML, got: #{inspect(context)}"
  end

  defp start_tags(html), do: start_tags(html, [])

  defp start_tags(<<"<!--", rest::binary>>, acc) do
    {_comment, rest} = take_until(rest, "-->")
    start_tags(rest, acc)
  end

  defp start_tags(<<"<!", rest::binary>>, acc) do
    {_declaration, rest} = take_until(rest, ">")
    start_tags(rest, acc)
  end

  defp start_tags(<<"<?", rest::binary>>, acc) do
    {_instruction, rest} = take_until(rest, ">")
    start_tags(rest, acc)
  end

  defp start_tags(<<"</", rest::binary>>, acc) do
    {_closing_tag, rest} = take_until(rest, ">")
    start_tags(rest, acc)
  end

  defp start_tags(<<"<", rest::binary>>, acc) do
    case take_start_tag(rest) do
      {:ok, tag, rest} -> start_tags(rest, [tag | acc])
      :error -> start_tags(rest, acc)
    end
  end

  defp start_tags(<<_char::utf8, rest::binary>>, acc), do: start_tags(rest, acc)
  defp start_tags(<<>>, acc), do: Enum.reverse(acc)

  defp take_start_tag(<<first::utf8, _rest::binary>> = html)
       when first in ?A..?Z or first in ?a..?z do
    {tag, rest} = take_tag(html, nil, "<")
    {:ok, tag, rest}
  end

  defp take_start_tag(_html), do: :error

  defp take_tag(<<>>, _quote, acc), do: {acc, ""}
  defp take_tag(<<">", rest::binary>>, nil, acc), do: {acc <> ">", rest}
  defp take_tag(<<"\"", rest::binary>>, nil, acc), do: take_tag(rest, ?", acc <> "\"")
  defp take_tag(<<"'", rest::binary>>, nil, acc), do: take_tag(rest, ?', acc <> "'")
  defp take_tag(<<"\"", rest::binary>>, ?", acc), do: take_tag(rest, nil, acc <> "\"")
  defp take_tag(<<"'", rest::binary>>, ?', acc), do: take_tag(rest, nil, acc <> "'")

  defp take_tag(<<char::utf8, rest::binary>>, quote, acc) do
    take_tag(rest, quote, acc <> <<char::utf8>>)
  end

  defp take_until(html, marker) do
    case String.split(html, marker, parts: 2) do
      [before, rest] -> {before <> marker, rest}
      [before] -> {before, ""}
    end
  end

  defp issues_for_tag(tag) do
    {name, attrs} = tag_name_and_attrs(tag)

    attrs
    |> duplicate_names()
    |> Enum.map(&issue_for(name, &1, tag))
  end

  defp tag_name_and_attrs("<" <> rest) do
    {name, rest} = take_name(rest, "")
    {String.downcase(name), parse_attrs(rest, [])}
  end

  defp take_name(<<>>, acc), do: {acc, ""}

  defp take_name(<<char::utf8, rest::binary>>, acc) when char in [?\s, ?\n, ?\r, ?\t, ?/, ?>] do
    {acc, <<char::utf8, rest::binary>>}
  end

  defp take_name(<<char::utf8, rest::binary>>, acc) do
    take_name(rest, acc <> <<char::utf8>>)
  end

  defp parse_attrs(<<>>, acc), do: Enum.reverse(acc)

  defp parse_attrs(<<char::utf8, rest::binary>>, acc) when char in [?\s, ?\n, ?\r, ?\t] do
    parse_attrs(rest, acc)
  end

  defp parse_attrs(<<char::utf8, _rest::binary>>, acc) when char in [?/, ?>] do
    Enum.reverse(acc)
  end

  defp parse_attrs(html, acc) do
    {name, rest} = take_attr_name(html, "")

    if name == "" do
      Enum.reverse(acc)
    else
      rest
      |> skip_attr_value()
      |> parse_attrs([String.downcase(name) | acc])
    end
  end

  defp take_attr_name(<<>>, acc), do: {acc, ""}

  defp take_attr_name(<<char::utf8, rest::binary>>, acc)
       when char in [?\s, ?\n, ?\r, ?\t, ?=, ?/, ?>] do
    {acc, <<char::utf8, rest::binary>>}
  end

  defp take_attr_name(<<char::utf8, rest::binary>>, acc) do
    take_attr_name(rest, acc <> <<char::utf8>>)
  end

  defp skip_attr_value(html) do
    html = skip_whitespace(html)

    case html do
      <<"=", rest::binary>> -> rest |> skip_whitespace() |> skip_value()
      _html -> html
    end
  end

  defp skip_whitespace(<<char::utf8, rest::binary>>) when char in [?\s, ?\n, ?\r, ?\t] do
    skip_whitespace(rest)
  end

  defp skip_whitespace(html), do: html

  defp skip_value(<<"\"", rest::binary>>), do: skip_quoted_value(rest, ?")
  defp skip_value(<<"'", rest::binary>>), do: skip_quoted_value(rest, ?')
  defp skip_value(html), do: skip_unquoted_value(html)

  defp skip_quoted_value(<<>>, _quote), do: ""
  defp skip_quoted_value(<<quote::utf8, rest::binary>>, quote), do: rest
  defp skip_quoted_value(<<_char::utf8, rest::binary>>, quote), do: skip_quoted_value(rest, quote)

  defp skip_unquoted_value(<<>>), do: ""

  defp skip_unquoted_value(<<char::utf8, _rest::binary>> = html)
       when char in [?\s, ?\n, ?\r, ?\t, ?>] do
    html
  end

  defp skip_unquoted_value(<<_char::utf8, rest::binary>>), do: skip_unquoted_value(rest)

  defp duplicate_names(attrs) do
    attrs
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> Enum.sort()
  end

  defp issue_for(tag, attr, snippet) do
    %Issue{
      check: __MODULE__,
      message: "expected <#{tag}> to define #{attr} only once",
      tag: tag,
      snippet: snippet
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
