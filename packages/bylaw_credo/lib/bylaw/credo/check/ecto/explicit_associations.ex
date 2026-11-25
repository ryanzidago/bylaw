defmodule Bylaw.Credo.Check.Ecto.ExplicitAssociations do
  @moduledoc """
  Persisted foreign-key fields in Ecto schemas should be declared as
  associations with `belongs_to`.

  ## Examples

  Avoid:

      schema "orders" do
        field :customer_id, :binary_id
      end

  Prefer:

      schema "orders" do
        belongs_to :customer, MyApp.Customer, type: :binary_id
      end

  `belongs_to` gives Ecto the relationship metadata used by preloads,
  association joins, changesets, and schema introspection. A plain field stores
  the value but leaves the relationship invisible to Ecto.

  This check inspects explicit `schema` blocks and reports persisted `field`
  declarations whose names end in `_id` unless a `belongs_to` in the same
  schema declares the corresponding foreign key. It does not expand shared
  schema macros.

  Option values must be statically visible in the field declaration. Only the
  literal `virtual: true` suppresses a field, and only the literal
  `primary_key: true` marks a field as a primary key; dynamic option values are
  treated conservatively as persisted non-primary fields.

  ## Options

  - `:ignore` - list of `{SchemaModule, field}` pairs for persisted identifiers
    that intentionally do not represent an Ecto association. Exemptions are
    scoped to one schema module and one field.

  ```elixir
  {Bylaw.Credo.Check.Ecto.ExplicitAssociations,
   [ignore: [{MyApp.ExternalRecord, :provider_id}]]}
  ```

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.ExplicitAssociations, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:database, :architecture],
    param_defaults: [ignore: []],
    explanations: [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    ignore = Params.get(params, :ignore, __MODULE__)
    issue_meta = IssueMeta.for(source_file, [])

    issues = module_issues(Credo.SourceFile.ast(source_file), nil, ignore, issue_meta)
    Enum.sort_by(issues, & &1.line_no)
  end

  defp module_issues(ast, parent, ignored, issue_meta) do
    ast
    |> body_expressions()
    |> Enum.flat_map(fn
      {:defmodule, _meta, [name, [do: body]]} ->
        module = module_name(name, parent)
        expressions = body_expressions(body)
        primary_key = primary_key_field(expressions)

        schema_issues =
          Enum.flat_map(expressions, &schema_issue(&1, module, primary_key, ignored, issue_meta))

        schema_issues ++ module_issues(expressions, module, ignored, issue_meta)

      _other ->
        []
    end)
  end

  defp schema_issue({:schema, _meta, args}, module, primary_key, ignored, issue_meta)
       when is_list(args) do
    case List.last(args) do
      [do: schema_body] -> fields_issues(schema_body, module, primary_key, ignored, issue_meta)
      _other -> []
    end
  end

  defp schema_issue(_expression, _module, _primary_key, _ignored, _issue_meta), do: []

  defp fields_issues(schema_body, module, primary_key, ignored, issue_meta) do
    expressions = body_expressions(schema_body)
    association_fields = Enum.flat_map(expressions, &association_fields/1)

    Enum.flat_map(
      expressions,
      &field_issue(&1, module, primary_key, association_fields, ignored, issue_meta)
    )
  end

  defp field_issue(
         {:field, meta, [name | rest]},
         module,
         primary_key,
         association_fields,
         ignored,
         issue_meta
       ) do
    name = literal_atom(name)
    options = field_options(rest)

    if foreign_key_name?(name) and persisted?(options) and
         not primary_key?(name, options, primary_key) and name not in association_fields and
         not ignored?(module, name, ignored) do
      [
        format_issue(
          issue_meta,
          message:
            "Persisted field `#{inspect(name)}` looks like a foreign key; declare a `belongs_to` association so Ecto can use its relationship metadata.",
          trigger: Atom.to_string(name),
          line_no: meta[:line]
        )
      ]
    else
      []
    end
  end

  defp field_issue(_expression, _module, _primary_key, _association_fields, _ignored, _meta),
    do: []

  defp association_fields({:belongs_to, _meta, [name | rest]}) do
    options = keyword_options(rest)
    [Keyword.get(options, :foreign_key, derived_foreign_key(literal_atom(name)))]
  end

  defp association_fields(_expression), do: []

  defp persisted?(options) do
    Keyword.get(options, :virtual) != true
  end

  defp foreign_key_name?(name) do
    name
    |> Atom.to_string()
    |> String.ends_with?("_id")
  end

  defp ignored?(module, name, ignored) when is_list(ignored), do: {module, name} in ignored
  defp ignored?(_module, _name, _ignored), do: false

  defp primary_key_field(expressions) do
    Enum.find_value(expressions, fn
      {:@, _meta, [{:primary_key, _attr_meta, [value]}]} -> primary_key_name(value)
      _other -> nil
    end)
  end

  defp primary_key_name({:{}, _meta, [name | _rest]}), do: literal_atom(name)
  defp primary_key_name(_value), do: nil

  defp primary_key?(name, options, primary_key) do
    name in [:id, primary_key] or Keyword.get(options, :primary_key) == true
  end

  defp field_options(rest), do: keyword_options(rest)

  defp keyword_options(rest) do
    case List.last(rest) do
      options when is_list(options) -> options
      _other -> []
    end
  end

  defp derived_foreign_key(name), do: String.to_atom("#{name}_id")

  defp literal_atom(name) when is_atom(name), do: name
  defp literal_atom(_name), do: nil

  defp module_name({:__aliases__, _meta, parts}, nil), do: Module.concat(parts)

  defp module_name({:__aliases__, _meta, [part]}, parent) when is_atom(parent),
    do: Module.concat(parent, part)

  defp module_name({:__aliases__, _meta, parts}, _parent), do: Module.concat(parts)
  defp module_name(module, _parent) when is_atom(module), do: module
  defp module_name(_module, _parent), do: nil

  defp body_expressions(expressions) when is_list(expressions), do: expressions
  defp body_expressions({:__block__, _meta, expressions}), do: expressions
  defp body_expressions(expression), do: [expression]
end
