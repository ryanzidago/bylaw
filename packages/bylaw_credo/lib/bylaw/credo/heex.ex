defmodule Bylaw.Credo.Heex do
  @moduledoc false

  # Internal HEEx helpers for Bylaw Credo checks.
  #
  # This module owns the optional Phoenix LiveView tokenizer boundary. Checks
  # consume the normalized templates and tags from here instead of calling
  # Phoenix tokenizer modules directly.

  defmodule Template do
    @moduledoc false

    # A HEEx template extracted from a source file.

    @enforce_keys [:source, :line, :column]
    defstruct [:source, :line, :column]

    @type t :: %__MODULE__{
            source: String.t(),
            line: pos_integer(),
            column: pos_integer()
          }
  end

  defmodule Tag do
    @moduledoc false

    # A normalized HEEx tag.

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
    @moduledoc false

    # Normalized HEEx text content.

    @enforce_keys [:content]
    defstruct [:content]

    @type t :: %__MODULE__{
            content: String.t()
          }
  end

  defmodule Expression do
    @moduledoc false

    # A normalized dynamic HEEx expression.

    @enforce_keys [:source, :line, :column]
    defstruct [:source, :line, :column]

    @type t :: %__MODULE__{
            source: String.t(),
            line: pos_integer(),
            column: pos_integer()
          }
  end

  defmodule CloseTag do
    @moduledoc false

    # A normalized HEEx closing tag.

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
  @tokenizer Phoenix.LiveView.Tokenizer
  @html_engine Phoenix.LiveView.HTMLEngine
  @tokenizer_available Code.ensure_loaded?(@tokenizer) and Code.ensure_loaded?(@html_engine)

  # Returns whether a compatible Phoenix LiveView tokenizer is available.
  @doc false
  @spec available?() :: boolean()
  def available? do
    @tokenizer_available
  end

  # Extracts HEEx templates from a Credo source file.
  @doc false
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

  # Tokenizes a HEEx template into normalized tags.
  @doc false
  @spec tags(Template.t() | String.t()) :: list(Tag.t())
  def tags(%Template{} = template) do
    template
    |> tokens()
    |> Enum.filter(&match?(%Tag{}, &1))
  end

  def tags(source) when is_binary(source) do
    tags(%Template{source: source, line: 1, column: 1})
  end

  # Tokenizes a HEEx template into normalized tokens.
  #
  # Returns an empty list if Phoenix LiveView is unavailable or the template
  # cannot be tokenized.
  @doc false
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

  # Returns whether a normalized tag contains the given attribute.
  @doc false
  @spec has_attr?(Tag.t(), String.t() | atom()) :: boolean()
  def has_attr?(%Tag{attrs: attrs}, name) do
    Enum.any?(attrs, &(&1.name == name))
  end

  defp heex_source_file?(filename) do
    Enum.any?(@heex_extensions, &String.ends_with?(filename, &1))
  end

  defp sigil_templates(source) do
    case Code.string_to_quoted(source, columns: true, token_metadata: true) do
      {:ok, ast} ->
        ast
        |> Macro.prewalk([], &collect_sigil_template/2)
        |> elem(1)
        |> Enum.reverse()

      _error ->
        []
    end
  end

  defp collect_sigil_template(
         {:sigil_H, meta, [{:<<>>, text_meta, parts}, _modifiers]} = ast,
         templates
       ) do
    source = IO.iodata_to_binary(parts)
    indentation = text_meta[:indentation] || 0
    line = sigil_line(meta)
    column = sigil_column(meta, source, indentation)

    {ast, [%Template{source: source, line: line, column: column} | templates]}
  end

  defp collect_sigil_template(ast, templates), do: {ast, templates}

  defp sigil_line(meta) do
    case meta[:delimiter] do
      "\"\"\"" -> (meta[:line] || 1) + 1
      _delimiter -> meta[:line] || 1
    end
  end

  defp sigil_column(meta, _source, indentation) do
    case meta[:delimiter] do
      "\"\"\"" -> indentation + 1
      delimiter -> (meta[:column] || 1) + 2 + String.length(delimiter || "")
    end
  end

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
    case EEx.tokenize(source) do
      {:ok, eex_nodes} ->
        {tokens, cont} =
          Enum.reduce(eex_nodes, {[], {:text, :enabled}}, fn node, acc ->
            tokenize_eex_node(node, acc, template, source)
          end)

        tokenizer_finalize(tokens, "nofile", cont, source)

      _error ->
        []
    end
  end

  defp tokenize_eex_node({:text, text, meta}, {tokens, cont}, template, source) do
    text = List.to_string(text)
    state = tokenizer_init(template.column - 1, "nofile", source)

    meta = [
      line: template.line + meta.line - 1,
      column: if(meta.line == 1, do: template.column + meta.column - 1, else: meta.column)
    ]

    tokenizer_tokenize(text, meta, tokens, cont, state)
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

    expr =
      expr
      |> List.to_string()
      |> String.trim()

    {[{:eex, type, expr, meta} | tokens], cont}
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

  if @tokenizer_available do
    alias Phoenix.LiveView.HTMLEngine
    alias Phoenix.LiveView.Tokenizer

    defp tokenizer_init(column, file, source) do
      Tokenizer.init(column, file, source, HTMLEngine)
    end

    defp tokenizer_tokenize(text, meta, tokens, cont, state) do
      Tokenizer.tokenize(text, meta, tokens, cont, state)
    end

    defp tokenizer_finalize(tokens, file, cont, source) do
      Tokenizer.finalize(tokens, file, cont, source)
    end
  else
    defp tokenizer_init(_column, _file, _source), do: nil
    defp tokenizer_tokenize(_text, _meta, tokens, cont, _state), do: {tokens, cont}
    defp tokenizer_finalize(_tokens, _file, _cont, _source), do: []
  end
end
