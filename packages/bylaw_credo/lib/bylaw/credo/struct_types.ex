defmodule Bylaw.Credo.StructTypes do
  @moduledoc """
  Checks explicit source declarations against compiled structs.

  Pass all modules owned by the application and their source file paths after
  compilation. Every struct must declare a public `@type t/0` or `@opaque t/0`
  whose own-struct branches explicitly list every compiled field. This includes
  fields introduced by macros, associations, metadata and exceptions.

  Sources are parsed, never evaluated. Type aliases and generated declarations
  that cannot be verified from source produce an error rather than an exemption.
  Compiled types alone cannot establish completeness: Elixir inserts `term()`
  for omitted struct fields.

      modules = Application.spec(:my_app, :modules)
      sources = Path.wildcard("lib/**/*.ex")
      :ok = Bylaw.Credo.StructTypes.validate(modules, sources)
  """

  @type issue :: %{
          module: module() | nil,
          file: String.t() | nil,
          line: pos_integer() | nil,
          reason: atom(),
          missing_fields: list(atom()),
          message: String.t()
        }

  @doc "Validates every compiled struct in `modules` against its source declaration."
  @spec validate(list(module()), list(String.t())) :: :ok | {:error, list(issue())}
  def validate(modules, source_files) when is_list(modules) and is_list(source_files) do
    {index, source_issues} = source_index(source_files)

    module_issues =
      modules
      |> Enum.uniq()
      |> Enum.flat_map(&validate_module(&1, index))

    issues = source_issues ++ module_issues

    if Enum.empty?(issues) do
      :ok
    else
      {:error, issues}
    end
  end

  defp source_index(files) do
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
              entry = %{file: file, line: meta[:line], types: []}
              acc = Map.put(acc, module, entry)
              scope = Map.put(scope, short_name(module), module)
              acc = collect(body, module, scope, file, acc)
              {acc, scope}
          end

        {:alias, _meta, args}, {acc, scope} ->
          {acc, add_alias(args, parent, scope)}

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

  defp module_name({:__MODULE__, _meta, _context}, parent, _aliases, _mode), do: parent

  defp module_name({:__aliases__, _meta, [:"Elixir" | rest]}, _parent, _aliases, _mode),
    do: Module.concat(rest)

  defp module_name(
         {:__aliases__, _meta, [{:__MODULE__, _module_meta, _context} | rest]},
         parent,
         _aliases,
         _mode
       )
       when parent != nil,
       do: Module.concat([parent | rest])

  defp module_name({:__aliases__, _meta, parts}, parent, _aliases, :definition)
       when parent != nil,
       do: Module.concat([parent | parts])

  defp module_name({:__aliases__, _meta, [first | rest]}, _parent, aliases, _mode)
       when is_atom(first) do
    prefix = Map.get(aliases, Atom.to_string(first), first)
    Module.concat([prefix | rest])
  end

  defp module_name(module, _parent, _aliases, _mode) when is_atom(module), do: module
  defp module_name(_ast, _parent, _aliases, _mode), do: nil

  defp validate_module(module, index) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :__struct__, 0) do
          validate_struct(module, index)
        else
          []
        end

      {:error, reason} ->
        [
          issue(
            module,
            nil,
            nil,
            :module_unavailable,
            [],
            "Cannot load module: #{inspect(reason)}"
          )
        ]
    end
  end

  defp validate_struct(module, index) do
    fields =
      module.__struct__()
      |> Map.keys()
      |> List.delete(:__struct__)
      |> Enum.sort()

    case Map.fetch(index, module) do
      :error ->
        [
          issue(
            module,
            nil,
            nil,
            :source_missing,
            fields,
            "No source declaration found for compiled struct"
          )
        ]

      {:ok, entry} ->
        types = Enum.filter(entry.types, &(&1.kind in [:type, :opaque]))

        if Enum.empty?(types) do
          [
            issue(
              module,
              entry.file,
              entry.line,
              :type_missing,
              fields,
              "Declare a public @type or @opaque t/0 with every struct field"
            )
          ]
        else
          Enum.flat_map(types, &validate_type(&1, module, fields, entry.file))
        end
    end
  end

  defp validate_type(type, module, fields, file) do
    case struct_branches(type.body, module, type.aliases) do
      {:ok, branches} ->
        Enum.flat_map(branches, &missing_field_issues(fields -- &1, module, file, type.line))

      :unsupported ->
        [
          issue(
            module,
            file,
            type.line,
            :type_unverifiable,
            [],
            "Cannot verify t/0; declare explicit own-struct field types in each branch"
          )
        ]
    end
  end

  defp missing_field_issues([], _module, _file, _line), do: []

  defp missing_field_issues(missing, module, file, line) do
    [
      issue(
        module,
        file,
        line,
        :fields_missing,
        missing,
        "Explicitly type missing struct fields: #{inspect(missing)}"
      )
    ]
  end

  defp struct_branches({:|, _meta, [left, right]}, module, aliases) do
    with {:ok, left_fields} <- struct_branches(left, module, aliases),
         {:ok, right_fields} <- struct_branches(right, module, aliases) do
      {:ok, left_fields ++ right_fields}
    else
      :unsupported -> :unsupported
    end
  end

  defp struct_branches({:%, _meta, [name, {:%{}, _fields_meta, fields}]}, module, aliases) do
    if module_name(name, module, aliases, :reference) == module && Keyword.keyword?(fields) do
      {:ok, [Keyword.keys(fields)]}
    else
      :unsupported
    end
  end

  defp struct_branches(_ast, _module, _aliases), do: :unsupported

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
