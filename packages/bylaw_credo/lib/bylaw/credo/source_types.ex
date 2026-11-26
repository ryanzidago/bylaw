defmodule Bylaw.Credo.SourceTypes do
  @moduledoc false

  @doc false
  @spec from_ast(Macro.t(), String.t()) :: map()
  def from_ast(ast, file), do: collect(ast, nil, %{}, file, %{})

  @doc false
  @spec index(list(String.t())) :: {map(), list(map())}
  def index(files) do
    files
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn file, {index, issues} ->
      with {:ok, source} <- File.read(file),
           {:ok, ast} <- Code.string_to_quoted(source) do
        {collect(ast, nil, %{}, file, index), issues}
      else
        error ->
          issue =
            issue(
              nil,
              file,
              nil,
              :source_unavailable,
              [],
              "Cannot parse source: #{inspect(error)}"
            )

          {index, [issue | issues]}
      end
    end)
  end

  defp collect(ast, parent, aliases, file, index) do
    {index, _aliases} =
      ast
      |> expressions()
      |> Enum.reduce({index, aliases}, fn
        {:defmodule, meta, [name, [do: body]]}, {acc, scope} ->
          case module_name(name, parent, scope, :definition) do
            nil ->
              {acc, scope}

            module ->
              entry = %{
                file: file,
                line: meta[:line],
                types: [],
                expressions: expressions(body),
                aliases: scope
              }

              acc = Map.put(acc, module, entry)
              scope = Map.put(scope, short_name(module), module)
              acc = collect(body, module, scope, file, acc)
              {acc, scope}
          end

        {:alias, _meta, args}, {acc, scope} ->
          scope = add_alias(args, parent, scope)

          {acc, scope}

        {:@, meta, [{kind, _kind_meta, [{:"::", _type_meta, [head, body]}]}]}, {acc, scope}
        when kind in [:type, :opaque, :typep] ->
          if parent && zero_t?(head) do
            type = %{kind: kind, body: body, aliases: scope, line: meta[:line]}
            {Map.update!(acc, parent, &%{&1 | types: [type | &1.types]}), scope}
          else
            {acc, scope}
          end

        _expression, state ->
          state
      end)

    index
  end

  defp expressions({:__block__, _meta, nodes}), do: nodes
  defp expressions(node), do: [node]
  defp zero_t?({:t, _meta, args}), do: args in [nil, []]
  defp zero_t?(_head), do: false

  @doc false
  @spec alias_scope(list(Macro.t()), module() | nil, map()) :: map()
  def alias_scope(args, parent, aliases), do: add_alias(args, parent, aliases)

  defp add_alias([{{:., _dot_meta, [prefix, :{}]}, _meta, names}], parent, aliases) do
    case module_name(prefix, parent, aliases, :reference) do
      nil -> aliases
      module -> Enum.reduce(names, aliases, &add_group_alias(&1, module, &2))
    end
  end

  defp add_alias([name | options], parent, aliases) do
    case module_name(name, parent, aliases, :reference) do
      nil ->
        aliases

      module ->
        as_option =
          options
          |> List.flatten()
          |> Keyword.get(:as)

        alias_name =
          case as_option do
            {:__aliases__, _meta, parts} ->
              parts
              |> List.last()
              |> Atom.to_string()

            _other ->
              short_name(module)
          end

        Map.put(aliases, alias_name, module)
    end
  end

  defp add_group_alias({:__aliases__, _meta, parts}, prefix, aliases) do
    module = Module.concat([prefix | parts])
    Map.put(aliases, short_name(module), module)
  end

  defp short_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  @doc false
  @spec module_name(Macro.t(), module() | nil, map(), atom()) :: module() | nil
  def module_name({:__MODULE__, _meta, _context}, parent, _aliases, _mode), do: parent

  def module_name({:__aliases__, _meta, [:"Elixir" | rest]}, _parent, _aliases, _mode),
    do: Module.concat(rest)

  def module_name(
        {:__aliases__, _meta, [{:__MODULE__, _module_meta, _context} | rest]},
        parent,
        _aliases,
        _mode
      )
      when parent != nil,
      do: Module.concat([parent | rest])

  def module_name({:__aliases__, _meta, parts}, parent, _aliases, :definition)
      when parent != nil,
      do: Module.concat([parent | parts])

  def module_name({:__aliases__, _meta, [first | rest]}, _parent, aliases, _mode)
      when is_atom(first) do
    prefix = Map.get(aliases, Atom.to_string(first), first)
    Module.concat([prefix | rest])
  end

  def module_name(module, _parent, _aliases, _mode) when is_atom(module), do: module
  def module_name(_ast, _parent, _aliases, _mode), do: nil

  @doc false
  @spec struct_branches(Macro.t(), module(), map()) :: {:ok, list(keyword())} | :unsupported
  def struct_branches({:|, _meta, [left, right]}, module, aliases) do
    with {:ok, left_fields} <- struct_branches(left, module, aliases),
         {:ok, right_fields} <- struct_branches(right, module, aliases) do
      {:ok, left_fields ++ right_fields}
    else
      :unsupported -> :unsupported
    end
  end

  def struct_branches({:%, _meta, [name, {:%{}, _fields_meta, fields}]}, module, aliases) do
    if module_name(name, module, aliases, :reference) == module && Keyword.keyword?(fields) do
      {:ok, [fields]}
    else
      :unsupported
    end
  end

  def struct_branches(_ast, _module, _aliases), do: :unsupported

  defp issue(module, file, line, reason, fields, message) do
    %{
      module: module,
      file: file,
      line: line,
      reason: reason,
      missing_fields: fields,
      message: message
    }
  end
end
