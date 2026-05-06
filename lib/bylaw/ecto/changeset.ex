defmodule Bylaw.Ecto.Changeset do
  @moduledoc """
  Extracts conservative changeset candidates from Ecto schema source files.

  A candidate is a function whose source AST directly calls `cast/3`,
  `cast/4`, `Ecto.Changeset.cast/3`, `Ecto.Changeset.cast/4`, `change/2`, or
  `Ecto.Changeset.change/2`. Literal cast/change fields are extracted for
  comparison with database constraints. Dynamic field lists are treated as
  unverifiable by returning an empty field list for v1.
  """

  defmodule Candidate do
    @moduledoc """
    A changeset-producing function found in a schema module.
    """

    @type t :: %__MODULE__{
            module: module(),
            function: atom(),
            arity: non_neg_integer(),
            fields: list(atom()),
            constraints: list(Bylaw.Ecto.Changeset.ConstraintCall.t())
          }

    defstruct module: nil,
              function: nil,
              arity: 0,
              fields: [],
              constraints: []
  end

  defmodule ConstraintCall do
    @moduledoc """
    A direct Ecto changeset constraint helper call.
    """

    @type kind :: :unique | :foreign_key | :check | :exclusion
    @type match :: :exact | :suffix | :prefix

    @type t :: %__MODULE__{
            kind: kind(),
            fields: list(atom()),
            name: String.t() | Regex.t() | nil,
            match: match()
          }

    defstruct kind: nil,
              fields: [],
              name: nil,
              match: :exact
  end

  @constraint_calls %{
    unique_constraint: :unique,
    foreign_key_constraint: :foreign_key,
    check_constraint: :check,
    exclusion_constraint: :exclusion
  }

  @doc """
  Returns changeset candidates found for the given schema modules and source paths.
  """
  @spec candidates(paths :: list(Path.t()), modules :: list(module())) :: list(Candidate.t())
  def candidates(paths, modules) when is_list(paths) and is_list(modules) do
    module_set = MapSet.new(modules)

    paths
    |> source_files()
    |> Enum.flat_map(&candidates_in_file(&1, module_set))
    |> Enum.sort_by(&{inspect(&1.module), &1.function, &1.arity})
  end

  defp source_files(paths) do
    paths
    |> Enum.flat_map(fn path ->
      cond do
        File.dir?(path) ->
          path
          |> Path.join("**/*.{ex,exs}")
          |> Path.wildcard()

        File.regular?(path) ->
          [path]

        true ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp candidates_in_file(path, module_set) do
    with {:ok, source} <- File.read(path),
         {:ok, quoted} <- Code.string_to_quoted(source) do
      modules_in_ast(quoted, module_set)
    else
      _error -> []
    end
  end

  defp modules_in_ast(ast, module_set) do
    {_ast, candidates} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [module_ast, [do: body]]} = node, candidates ->
          module = module_name(module_ast)

          if MapSet.member?(module_set, module) do
            {node, function_candidates(module, body) ++ candidates}
          else
            {node, candidates}
          end

        node, candidates ->
          {node, candidates}
      end)

    candidates
  end

  defp module_name({:__aliases__, _meta, parts}), do: Module.concat(parts)
  defp module_name(module) when is_atom(module), do: module
  defp module_name(_ast), do: nil

  defp function_candidates(module, {:__block__, _meta, expressions}) do
    Enum.flat_map(expressions, &function_candidate(module, &1))
  end

  defp function_candidates(module, expression), do: function_candidate(module, expression)

  defp function_candidate(module, {kind, _meta, [head, [do: body]]}) when kind in [:def, :defp] do
    {function, arity} = function_name_arity(head)
    fields = candidate_fields(body)

    if Enum.empty?(fields) do
      []
    else
      [
        %Candidate{
          module: module,
          function: function,
          arity: arity,
          fields: fields,
          constraints: constraint_calls(body)
        }
      ]
    end
  end

  defp function_candidate(_module, _expression), do: []

  defp function_name_arity({:when, _meta, [head | _guards]}), do: function_name_arity(head)

  defp function_name_arity({name, _meta, args}) when is_atom(name) do
    {name, Enum.count(args || [])}
  end

  defp function_name_arity(_head), do: {nil, 0}

  defp candidate_fields(ast) do
    ast
    |> collect_calls(&cast_or_change_fields/1)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp constraint_calls(ast) do
    ast
    |> collect_calls(&constraint_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp collect_calls(ast, mapper) do
    {_ast, values} =
      Macro.prewalk(ast, [], fn node, values ->
        case mapper.(node) do
          [] -> {node, values}
          nil -> {node, values}
          value -> {node, [value | values]}
        end
      end)

    Enum.reverse(values)
  end

  defp cast_or_change_fields({name, _meta, args})
       when name in [:cast, :change] and is_list(args) do
    local_changeset_fields(name, args)
  end

  defp cast_or_change_fields({{:., _meta, [module, name]}, _call_meta, args})
       when name in [:cast, :change] and is_list(args) do
    if ecto_changeset_module?(module) do
      remote_changeset_fields(name, args)
    else
      []
    end
  end

  defp cast_or_change_fields(_node), do: []

  defp local_changeset_fields(:cast, args), do: cast_fields(args)
  defp local_changeset_fields(:change, [changes]), do: literal_change_fields(changes)
  defp local_changeset_fields(:change, [_data, changes]), do: literal_change_fields(changes)
  defp local_changeset_fields(_name, _args), do: []

  defp remote_changeset_fields(:cast, args), do: cast_fields(args)
  defp remote_changeset_fields(:change, [changes]), do: literal_change_fields(changes)
  defp remote_changeset_fields(:change, [_data, changes]), do: literal_change_fields(changes)
  defp remote_changeset_fields(_name, _args), do: []

  defp cast_fields([_params, fields]), do: literal_atom_list(fields)

  defp cast_fields([_first, second, third]) do
    case literal_atom_list(second) do
      [] -> literal_atom_list(third)
      fields -> fields
    end
  end

  defp cast_fields([_data, _params, fields, _opts]), do: literal_atom_list(fields)
  defp cast_fields(_args), do: []

  defp literal_atom_list(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1), do: fields, else: []
  end

  defp literal_atom_list(_fields), do: []

  defp literal_change_fields({:%{}, _meta, pairs}) when is_list(pairs) do
    pairs
    |> Enum.flat_map(fn
      {key, _value} when is_atom(key) -> [key]
      _pair -> []
    end)
    |> Enum.sort()
  end

  defp literal_change_fields(changes) when is_list(changes) do
    if Keyword.keyword?(changes), do: Keyword.keys(changes), else: []
  end

  defp literal_change_fields(_changes), do: []

  defp constraint_call({name, _meta, args})
       when is_map_key(@constraint_calls, name) and is_list(args) do
    constraint_call(Map.fetch!(@constraint_calls, name), args)
  end

  defp constraint_call({{:., _meta, [module, name]}, _call_meta, args})
       when is_map_key(@constraint_calls, name) and is_list(args) do
    if ecto_changeset_module?(module) do
      constraint_call(Map.fetch!(@constraint_calls, name), args)
    end
  end

  defp constraint_call(_node), do: nil

  defp constraint_call(kind, args) do
    {field_arg, opts_arg} = constraint_args(args)

    %ConstraintCall{
      kind: kind,
      fields: constraint_fields(field_arg),
      name: constraint_name(opts_arg),
      match: constraint_match(opts_arg)
    }
  end

  defp constraint_args([field]), do: {field, []}
  defp constraint_args([field, opts]) when is_list(opts), do: {field, opts}
  defp constraint_args([_changeset, field]), do: {field, []}
  defp constraint_args([_changeset, field, opts]), do: {field, opts}
  defp constraint_args(_args), do: {nil, []}

  defp constraint_fields(field) when is_atom(field), do: [field]
  defp constraint_fields(fields) when is_list(fields), do: literal_atom_list(fields)
  defp constraint_fields(_field), do: []

  defp constraint_name(opts) when is_list(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} when is_atom(name) -> Atom.to_string(name)
      {:ok, name} when is_binary(name) -> name
      {:ok, name} -> literal_regex(name)
      _other -> nil
    end
  end

  defp constraint_name(_opts), do: nil

  defp constraint_match(opts) when is_list(opts) do
    case Keyword.fetch(opts, :match) do
      {:ok, match} when match in [:exact, :suffix, :prefix] -> match
      _other -> :exact
    end
  end

  defp constraint_match(_opts), do: :exact

  defp literal_regex({:sigil_r, _meta, [{:<<>>, _string_meta, [source]}, modifiers]})
       when is_binary(source) and is_list(modifiers) do
    case Regex.compile(source, to_string(modifiers)) do
      {:ok, regex} -> regex
      {:error, _reason} -> nil
    end
  end

  defp literal_regex(_name), do: nil

  defp ecto_changeset_module?({:__aliases__, _meta, [:Ecto, :Changeset]}), do: true
  defp ecto_changeset_module?(Ecto.Changeset), do: true
  defp ecto_changeset_module?(_module), do: false
end
