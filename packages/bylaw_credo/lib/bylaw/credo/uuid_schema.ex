defmodule Bylaw.Credo.UUIDSchema do
  @moduledoc false

  alias Bylaw.Credo.SourceTypes

  @doc false
  @spec uuid_type?(term()) :: boolean()
  def uuid_type?(type), do: type in [:binary_id, Ecto.UUID]

  @doc false
  @spec invalid_fields(map(), module(), list(atom())) :: list({pos_integer(), list(atom())})
  def invalid_fields(_entry, _module, []), do: []

  def invalid_fields(entry, module, fields) do
    entry.types
    |> Enum.filter(&(&1.kind in [:type, :opaque]))
    |> Enum.flat_map(&invalid_type_fields(&1, module, fields))
  end

  defp invalid_type_fields(type, module, fields) do
    invalid =
      case SourceTypes.struct_branches(type.body, module, type.aliases) do
        {:ok, branches} ->
          Enum.filter(fields, &invalid_field?(&1, branches, module, type.aliases))

        :unsupported ->
          fields
      end

    if Enum.empty?(invalid) do
      []
    else
      [{type.line, invalid}]
    end
  end

  defp invalid_field?(field, branches, module, aliases) do
    Enum.any?(branches, fn branch ->
      branch
      |> Keyword.get(field)
      |> precise_uuid?(module, aliases)
      |> Kernel.not()
    end)
  end

  @doc false
  @spec static_fields(map(), module()) :: list(atom())
  def static_fields(entry, module) do
    initial = %{
      primary_key: :unknown,
      foreign_key: :unknown,
      native: false,
      aliases: entry.aliases
    }

    {_state, fields} =
      Enum.reduce(entry.expressions, {initial, []}, fn expression, {state, found} ->
        case expression do
          {:alias, _meta, args} ->
            {%{state | aliases: SourceTypes.alias_scope(args, module, state.aliases)}, found}

          {:use, _meta, [name | _opts]} ->
            native = resolve(name, module, state.aliases) == Ecto.Schema
            {%{state | native: native or state.native}, found}

          {:@, _meta, [{:primary_key, _attr_meta, [value]}]} ->
            {%{state | primary_key: primary_key_value(value, module, state.aliases)}, found}

          {:@, _meta, [{:foreign_key_type, _attr_meta, [value]}]} ->
            {%{state | foreign_key: resolve_type(value, module, state.aliases)}, found}

          {kind, _meta, args} when kind in [:schema, :embedded_schema] and is_list(args) ->
            {state, found ++ schema_fields(args, kind, state, module, state.aliases)}

          _other ->
            {state, found}
        end
      end)

    Enum.uniq(fields)
  end

  defp schema_fields(args, kind, state, module, aliases) do
    case List.last(args) do
      [do: body] ->
        primary = primary_field(state, kind, module, aliases)

        foreign =
          if state.foreign_key == :unknown and state.native do
            :id
          else
            state.foreign_key
          end

        declared =
          body
          |> expressions()
          |> Enum.flat_map(&field(&1, foreign, module, aliases))

        primary ++ declared

      _other ->
        []
    end
  end

  defp primary_key_value({:{}, meta, [name, type | options]}, module, aliases) do
    {:{}, meta, [name, resolve_type(type, module, aliases) | options]}
  end

  defp primary_key_value(value, _module, _aliases), do: value

  defp primary_field(
         %{primary_key: {:{}, _tuple_meta, [name, type | _options]}},
         _kind,
         module,
         aliases
       ) do
    type
    |> resolve_type(module, aliases)
    |> uuid_type?()
    |> selected_field(name)
  end

  defp primary_field(%{primary_key: :unknown, native: true}, :embedded_schema, _module, _aliases),
    do: [:id]

  defp primary_field(_state, _kind, _module, _aliases), do: []

  defp field({:field, _meta, [name, type | _options]}, _foreign, module, aliases) do
    type
    |> resolve_type(module, aliases)
    |> uuid_type?()
    |> selected_field(name)
  end

  defp field({:belongs_to, _meta, [name, _target | rest]}, foreign, module, aliases) do
    opts =
      case List.last(rest) do
        options when is_list(options) -> options
        _other -> []
      end

    type = resolve_type(Keyword.get(opts, :type, foreign), module, aliases)

    if is_atom(name) and Keyword.get(opts, :define_field) != false and uuid_type?(type) do
      [Keyword.get(opts, :foreign_key, String.to_atom("#{name}_id"))]
    else
      []
    end
  end

  defp field(_expression, _foreign, _module, _aliases), do: []

  defp selected_field(true, name) when is_atom(name), do: [name]
  defp selected_field(_selected, _name), do: []

  defp precise_uuid?({:|, _meta, [left, right]}, module, aliases) do
    branches = union_branches({:|, [], [left, right]})

    Enum.any?(branches, &uuid_reference?(&1, module, aliases)) and
      Enum.all?(branches, &(&1 == nil or uuid_reference?(&1, module, aliases)))
  end

  defp precise_uuid?(type, module, aliases), do: uuid_reference?(type, module, aliases)

  defp uuid_reference?({{:., _dot_meta, [name, :t]}, _meta, []}, module, aliases),
    do: resolve(name, module, aliases) == Ecto.UUID

  defp uuid_reference?(_type, _module, _aliases), do: false

  defp union_branches({:|, _meta, [left, right]}),
    do: union_branches(left) ++ union_branches(right)

  defp union_branches(type), do: [type]
  defp resolve_type(type, _module, _aliases) when is_atom(type), do: type
  defp resolve_type(type, module, aliases), do: resolve(type, module, aliases)

  defp resolve(name, module, aliases),
    do: SourceTypes.module_name(name, module, aliases, :reference)

  defp expressions({:__block__, _meta, expressions}), do: expressions
  defp expressions(expression), do: [expression]
end
