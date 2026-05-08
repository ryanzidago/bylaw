defmodule Bylaw.Credo.Heex do
  @moduledoc """
  Small HEEx helpers for Bylaw Credo checks.

  This module owns the optional Phoenix LiveView tokenizer boundary. Checks should
  consume the normalized templates and tags from this module instead of calling
  Phoenix tokenizer modules directly.
  """

  defmodule Template do
    @moduledoc """
    A HEEx template extracted from a source file.
    """

    @enforce_keys [:source, :line, :column]
    defstruct [:source, :line, :column]

    @type t :: %__MODULE__{
            source: String.t(),
            line: pos_integer(),
            column: pos_integer()
          }
  end

  defmodule Tag do
    @moduledoc """
    A normalized HEEx tag.
    """

    @enforce_keys [:type, :name, :attrs, :line, :column]
    defstruct [:type, :name, :attrs, :line, :column, :closing]

    @type attr :: %{
            name: String.t() | :root,
            value: term(),
            line: pos_integer() | nil,
            column: pos_integer() | nil
          }

    @type t :: %__MODULE__{
            type: atom(),
            name: String.t(),
            attrs: list(attr()),
            line: pos_integer(),
            column: pos_integer(),
            closing: atom() | nil
          }
  end

  defmodule Text do
    @moduledoc """
    Normalized HEEx text content.
    """

    @enforce_keys [:content]
    defstruct [:content]

    @type t :: %__MODULE__{
            content: String.t()
          }
  end

  defmodule Expression do
    @moduledoc """
    A normalized dynamic HEEx expression.
    """

    @enforce_keys [:source, :line, :column]
    defstruct [:source, :line, :column]

    @type t :: %__MODULE__{
            source: String.t(),
            line: pos_integer(),
            column: pos_integer()
          }
  end

  defmodule CloseTag do
    @moduledoc """
    A normalized HEEx closing tag.
    """

    @enforce_keys [:name, :line, :column]
    defstruct [:name, :line, :column]

    @type t :: %__MODULE__{
            name: String.t(),
            line: pos_integer(),
            column: pos_integer()
          }
  end

  @type token :: Tag.t() | Text.t() | Expression.t() | CloseTag.t()

  @eex_expr [:start_expr, :expr, :end_expr, :middle_expr]
  @heex_extensions [".ex", ".exs"]
  @tag_engine_tokenizer Module.concat([Phoenix, LiveView, TagEngine, Tokenizer])
  @tokenizer Module.concat([Phoenix, LiveView, Tokenizer])
  @html_engine Module.concat([Phoenix, LiveView, HTMLEngine])

  @doc """
  Returns whether a compatible Phoenix LiveView tokenizer is available.
  """
  @spec available?() :: boolean()
  def available? do
    not is_nil(tokenizer_module()) and Code.ensure_loaded?(@html_engine)
  end

  @doc """
  Extracts HEEx templates from a Credo source file.
  """
  @spec templates(Credo.SourceFile.t()) :: list(Template.t())
  def templates(%Credo.SourceFile{} = source_file) do
    source = Credo.SourceFile.source(source_file)

    cond do
      String.ends_with?(source_file.filename, ".html.heex") ->
        [%Template{source: source, line: 1, column: 1}]

      heex_source_file?(source_file.filename) ->
        sigil_templates(source)

      true ->
        []
    end
  end

  @doc """
  Tokenizes a HEEx template into normalized tags.

  Returns an empty list if Phoenix LiveView is unavailable or the template cannot
  be tokenized.
  """
  @spec tags(Template.t() | String.t()) :: list(Tag.t())
  def tags(%Template{} = template) do
    template
    |> tokens()
    |> Enum.filter(&match?(%Tag{}, &1))
  end

  def tags(source) when is_binary(source) do
    tags(%Template{source: source, line: 1, column: 1})
  end

  @doc """
  Tokenizes a HEEx template into normalized tokens.

  Returns an empty list if Phoenix LiveView is unavailable or the template cannot
  be tokenized.
  """
  @spec tokens(Template.t() | String.t()) :: list(token())
  def tokens(%Template{} = template) do
    if available?() do
      do_tokens(template)
    else
      []
    end
  end

  def tokens(source) when is_binary(source) do
    tokens(%Template{source: source, line: 1, column: 1})
  end

  @doc """
  Returns whether a normalized tag contains the given attribute.
  """
  @spec has_attr?(Tag.t(), String.t() | atom()) :: boolean()
  def has_attr?(%Tag{attrs: attrs}, name) do
    Enum.any?(attrs, &(&1.name == name))
  end

  defp heex_source_file?(filename) do
    Enum.any?(@heex_extensions, &String.ends_with?(filename, &1))
  end

  defp sigil_templates(source) do
    with {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
      ast
      |> Macro.prewalk([], &collect_sigil_template/2)
      |> elem(1)
      |> Enum.reverse()
    else
      _error -> []
    end
  end

  defp collect_sigil_template(
         {:sigil_H, meta, [{:<<>>, text_meta, parts}, _modifiers]} = ast,
         templates
       ) do
    source = IO.iodata_to_binary(parts)
    indentation = text_meta[:indentation] || 0

    line =
      case meta[:delimiter] do
        "\"\"\"" -> (meta[:line] || 1) + 1
        _other -> meta[:line] || 1
      end

    column =
      case meta[:delimiter] do
        "\"\"\"" -> indentation + 1
        delimiter -> (meta[:column] || 1) + 2 + String.length(delimiter || "")
      end

    {ast, [%Template{source: source, line: line, column: column} | templates]}
  end

  defp collect_sigil_template(ast, templates), do: {ast, templates}

  defp do_tokens(%Template{} = template) do
    template.source
    |> tokenize(template)
    |> Enum.flat_map(&normalize_token/1)
  rescue
    _error -> []
  catch
    _kind, _value -> []
  end

  defp tokenize(source, template) do
    with {:ok, eex_nodes} <- EEx.tokenize(source) do
      {tokens, cont} =
        Enum.reduce(eex_nodes, {[], {:text, :enabled}}, fn node, acc ->
          tokenize_eex_node(node, acc, template, source)
        end)

      tokenizer = tokenizer_module()
      apply(tokenizer, :finalize, [tokens, "nofile", cont, source])
    else
      _error -> []
    end
  end

  defp tokenize_eex_node({:text, text, meta}, {tokens, cont}, template, source) do
    text = List.to_string(text)
    tokenizer = tokenizer_module()
    state = apply(tokenizer, :init, [template.column - 1, "nofile", source, @html_engine])

    meta = [
      line: template.line + meta.line - 1,
      column: if(meta.line == 1, do: template.column + meta.column - 1, else: meta.column)
    ]

    apply(tokenizer, :tokenize, [text, meta, tokens, cont, state])
  end

  defp tokenize_eex_node({:comment, text, meta}, {tokens, cont}, _template, _source) do
    {[{:eex_comment, List.to_string(text), meta} | tokens], cont}
  end

  defp tokenize_eex_node(
         {type, opt, expr, %{column: column, line: line}},
         {tokens, cont},
         _template,
         _source
       )
       when type in @eex_expr do
    meta = %{opt: opt, line: line, column: column}
    {[{:eex, type, expr |> List.to_string() |> String.trim(), meta} | tokens], cont}
  end

  defp tokenize_eex_node(_node, acc, _template, _source), do: acc

  defp normalize_token({type, name, attrs, meta})
       when type in [:tag, :local_component, :remote_component, :slot] do
    [
      %Tag{
        type: type,
        name: name,
        attrs: Enum.map(attrs, &normalize_attr/1),
        line: meta.line,
        column: meta.column,
        closing: meta[:closing]
      }
    ]
  end

  defp normalize_token({:close, :tag, name, meta}) do
    [
      %CloseTag{
        name: name,
        line: meta.line,
        column: meta.column
      }
    ]
  end

  defp normalize_token({:text, content, _meta}) do
    [%Text{content: content}]
  end

  defp normalize_token({:eex, _type, source, meta}) do
    [
      %Expression{
        source: source,
        line: meta.line,
        column: meta.column
      }
    ]
  end

  defp normalize_token({:body_expr, source, meta}) do
    [
      %Expression{
        source: source,
        line: meta.line,
        column: meta.column
      }
    ]
  end

  defp normalize_token(_token), do: []

  defp normalize_attr({name, value, meta}) do
    %{
      name: name,
      value: value,
      line: meta[:line],
      column: meta[:column]
    }
  end

  defp tokenizer_module do
    cond do
      Code.ensure_loaded?(@tag_engine_tokenizer) -> @tag_engine_tokenizer
      Code.ensure_loaded?(@tokenizer) -> @tokenizer
      true -> nil
    end
  end
end
