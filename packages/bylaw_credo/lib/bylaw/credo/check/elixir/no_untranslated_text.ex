defmodule Bylaw.Credo.Check.Elixir.NoUntranslatedText do
  @moduledoc """
  Forbid literal, readable text passed straight to a function that shows it to a person, so every word comes from `gettext/1`.

  ## Examples

  Avoid:

        def delete(socket) do
          put_flash(socket, :info, "Saved")
        end

        def mount(_params, _session, socket) do
          {:ok, assign(socket, page_title: "Orders")}
        end

  Prefer:

        def delete(socket) do
          put_flash(socket, :info, gettext("Saved"))
        end

        def mount(_params, _session, socket) do
          {:ok, assign(socket, page_title: gettext("Orders"))}
        end

  A text written into Elixir code and handed to a flash, a page title or an
  email is shown in one language to every visitor, and nothing fails when a
  translator never sees it. Routing it through gettext puts it in the extracted
  `.pot` files, where missing translations are visible. Templates have the same
  problem, and `Bylaw.Credo.Check.HEEx.NoUntranslatedText` covers them.

  The check reports a string literal, an interpolated string, a heredoc or a
  `<>` join with one of them, when it contains a letter from any script
  (`\\p{L}`) and is an argument of a configured sink. A sink is a function
  name, an arity and the argument positions that a person reads. A call
  piped into counts the piped value as the first argument. It also reports a
  literal assigned to one of `:assign_keys` with `assign/2` or `assign/3`.

  It allows text made only of punctuation, digits, whitespace and symbols,
  and every argument that is not a literal: a variable, a call such as
  `gettext/1` or `dgettext/2`, `gettext_noop/1`, a module attribute. Arguments
  of calls that are not sinks are not looked at, so a log line, a map key or a
  route is never reported.

  A text that is meant literally, such as a language's own name, is exempted
  with Credo's comment on the line before the call:

  ```elixir
  # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoUntranslatedText
  put_flash(socket, :info, "Deutsch")
  ```

  `Bylaw.Credo.Plugin.DisableForNextDefinition` does the same for a whole
  function.

  Not detected: text that reaches a sink through a variable or another
  function, a call through a variable module, and text returned from a
  function to be shown elsewhere.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoUntranslatedText,
           [
             sinks: [{:put_flash, 3, [3]}, {:deliver, 3, [2, 3]}],
             assign_keys: [:page_title]
           ]}
        ]
      }
    ]
  }
  ```

  - `:sinks` - The functions that show an argument to a person, as
    `{function, arity, positions}` or `{module, function, arity, positions}`.
    Positions count from 1, so `{:put_flash, 3, [3]}` is the message of
    `put_flash(conn, key, message)`. A sink without a module matches the
    function when it is called locally, through an import or with any module;
    a sink with a module matches only a call written with that module, aliases
    resolved. Defaults to `put_flash/3`, position 3, which Phoenix's
    `Phoenix.Controller` and `Phoenix.LiveView` both define. Defaults are
    replaced, not extended: list `put_flash` again when you add your own.
  - `:assign_keys` - Assign keys whose literal values people read. Defaults to
    `[:page_title]`.

  Use Credo's per-check `files: %{excluded: [...]}` option to skip code that is
  not translated yet.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoUntranslatedText, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:web],
    param_defaults: [
      sinks: [{:put_flash, 3, [3]}],
      assign_keys: [:page_title]
    ],
    explanations: [
      check: @moduledoc,
      params: [
        sinks:
          "`{function, arity, positions}` or `{module, function, arity, positions}` for each function that shows an argument to a person.",
        assign_keys: "Assign keys whose literal values people read."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @letter ~r/\p{L}/u
  @max_trigger 60

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    ast = Credo.SourceFile.ast(source_file)
    sinks = Params.get(params, :sinks, __MODULE__)

    context = %{
      aliases: RemoteCalls.aliases(ast),
      sinks: Enum.map(sinks, &sink/1),
      assign_keys: Params.get(params, :assign_keys, __MODULE__)
    }

    ast
    |> visit(false, context)
    |> Enum.sort_by(fn {line, _text, _sink} -> line end)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp sink({function, arity, positions}), do: sink({nil, function, arity, positions})

  defp sink({module, function, arity, positions}) do
    %{
      module: module && RemoteCalls.module_name(module),
      function: function,
      arity: arity,
      positions: positions
    }
  end

  defp visit({:|>, _meta, [left, right]}, _piped, context) do
    visit(left, false, context) ++ visit(right, true, context)
  end

  defp visit({{:., _dot_meta, [module_ast, function]}, meta, args}, piped, context)
       when is_atom(function) and is_list(args) do
    module = RemoteCalls.resolve(module_ast, context.aliases)

    findings(module, function, meta, args, piped, context) ++
      visit(module_ast, false, context) ++ visit(args, false, context)
  end

  defp visit({kind, _meta, [head | rest]}, _piped, context)
       when kind in [:def, :defp, :defmacro, :defmacrop] do
    visit(head_arguments(head), false, context) ++ visit(rest, false, context)
  end

  defp visit({name, meta, args}, piped, context) when is_atom(name) and is_list(args) do
    findings(nil, name, meta, args, piped, context) ++ visit(args, false, context)
  end

  defp visit({form, _meta, args}, _piped, context) when is_list(args) do
    visit(form, false, context) ++ visit(args, false, context)
  end

  defp visit({left, right}, _piped, context) do
    visit(left, false, context) ++ visit(right, false, context)
  end

  defp visit(list, _piped, context) when is_list(list) do
    Enum.flat_map(list, &visit(&1, false, context))
  end

  defp visit(_other, _piped, _context), do: []

  defp head_arguments({:when, _meta, [head, guard]}), do: [guard | head_arguments(head)]
  defp head_arguments({_name, _meta, args}) when is_list(args), do: args
  defp head_arguments(_head), do: []

  defp piped_offset(true), do: 1
  defp piped_offset(false), do: 0

  defp findings(module, function, meta, args, piped, context) do
    offset = piped_offset(piped)
    arity = Enum.count(args) + offset
    line = meta[:line] || 0

    sinks = Enum.filter(context.sinks, &sink_match?(&1, module, function, arity))

    sink_findings =
      for sink <- sinks,
          position <- sink.positions,
          argument = argument_at(args, position - 1 - offset),
          text = text(argument),
          do: {line, text, "#{function}/#{arity}"}

    sink_findings ++ assign_findings(function, arity, offset, args, line, context)
  end

  defp sink_match?(sink, module, function, arity) do
    sink.function == function and sink.arity == arity and
      (sink.module == nil or sink.module == module)
  end

  defp argument_at(args, index) when index >= 0, do: Enum.at(args, index)
  defp argument_at(_args, _index), do: nil

  defp assign_findings(:assign, 3, offset, args, line, context) do
    with key when is_atom(key) <- argument_at(args, 1 - offset),
         true <- key in context.assign_keys,
         text when is_binary(text) <- text(argument_at(args, 2 - offset)) do
      [{line, text, "assign/3 #{inspect(key)}"}]
    else
      _other -> []
    end
  end

  defp assign_findings(:assign, 2, offset, args, line, context) do
    args
    |> argument_at(1 - offset)
    |> pairs()
    |> Enum.flat_map(fn {key, value} ->
      with true <- key in context.assign_keys,
           text when is_binary(text) <- text(value) do
        [{line, text, "assign/2 #{inspect(key)}"}]
      else
        _other -> []
      end
    end)
  end

  defp assign_findings(_function, _arity, _offset, _args, _line, _context), do: []

  defp pairs({:%{}, _meta, pairs}) when is_list(pairs),
    do: Enum.filter(pairs, &match?({_, _}, &1))

  defp pairs(list) when is_list(list), do: Enum.filter(list, &match?({_, _}, &1))
  defp pairs(_other), do: []

  defp text(literal) when is_binary(literal) do
    if Regex.match?(@letter, literal) do
      squish(literal)
    end
  end

  defp text({:<<>>, _meta, parts}) when is_list(parts) do
    literal = for part <- parts, is_binary(part), into: "", do: part

    if Regex.match?(@letter, literal) do
      parts
      |> Enum.map_join(fn
        part when is_binary(part) -> part
        _interpolation -> "\#{…}"
      end)
      |> squish()
    end
  end

  defp text({:<>, _meta, [left, right]}), do: text(left) || text(right)
  defp text(_other), do: nil

  defp squish(text) do
    text
    |> String.split()
    |> Enum.join(" ")
  end

  defp issue_for(issue_meta, {line_no, text, sink}) do
    format_issue(issue_meta,
      message:
        "Translate #{inspect(text)}: it is shown to a person through #{sink}, so " <>
          ~S|build it with gettext, such as gettext("…").|,
      trigger: String.slice(text, 0, @max_trigger),
      line_no: line_no
    )
  end
end
