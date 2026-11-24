defmodule Bylaw.Credo.Check.Elixir.BooleanFieldsIsPrefix do
  @moduledoc """
  Name every boolean field with the `is_` prefix: a boolean says what it is,
  not what it holds.

  ## Examples

  Avoid:

        schema "options" do
          field :active, :boolean, default: true
        end

        @type t :: %__MODULE__{active: boolean()}

        %{active: %Schema{type: :boolean}}

  Prefer:

        schema "options" do
          field :is_active, :boolean, default: true
        end

        @type t :: %__MODULE__{is_active: boolean()}

        %{is_active: %Schema{type: :boolean}}

  An unprefixed name reads as a thing: `delivery: true` could be a flag or a
  nested value, `card: true` could be a card. `is_delivery_enabled` and
  `is_card_accepted` cannot be misread. The prefix is for data fields only; a
  predicate function ends in `?`, as Elixir convention and Credo's
  `PredicateFunctionNames` say, and this check leaves functions alone.

  The check reports:

  - `field :name, :boolean` (also with options) anywhere, so Ecto schemas and
    embedded schemas are both covered;
  - `add :name, :boolean` in a migration;
  - a map or struct key typed `boolean()` or `boolean() | nil` inside `@type`,
    `@typep`, `@opaque`, `@spec`, `@callback` and `@macrocallback`;
  - a map key whose value is an OpenApiSpex `Schema` with `type: :boolean`
    (written `%Schema{type: :boolean, ...}` or
    `%OpenApiSpex.Schema{type: :boolean, ...}`), the property a schema module
    exposes.

  A type in a variable, `{:array, :boolean}` (a list of booleans is a list,
  not a flag) and a bare `boolean()` in a function's parameter or return
  position are not reported: only keys and fields carry a name that can be
  misread.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.BooleanFieldsIsPrefix,
           [allowed_prefixes: ["is_"]]}
        ]
      }
    ]
  }
  ```

  - `:allowed_prefixes` - A field is compliant when its name starts with any
    of these. Defaults to `["is_"]`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.BooleanFieldsIsPrefix, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [allowed_prefixes: ["is_"]],
    explanations: [
      check: @moduledoc,
      params: [
        allowed_prefixes: "A field is compliant when its name starts with one of these prefixes."
      ]
    ]

  @type_attributes [:type, :typep, :opaque, :spec, :callback, :macrocallback]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed = Params.get(params, :allowed_prefixes, __MODULE__)
    ast = Credo.SourceFile.ast(source_file)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:@, _meta, [{attribute, _meta2, [value]}]} = node, issues
        when attribute in @type_attributes ->
          {node, type_issues(value, allowed, issue_meta) ++ issues}

        {:field, meta, [name, type | _rest]} = node, issues ->
          {node, boolean_issue(name, type, meta, issue_meta, allowed) ++ issues}

        {:add, meta, [name, type | _rest]} = node, issues ->
          {node, boolean_issue(name, type, meta, issue_meta, allowed) ++ issues}

        {:%{}, meta, pairs} = node, issues when is_list(pairs) ->
          {node, property_issues(pairs, meta, issue_meta, allowed) ++ issues}

        node, issues ->
          {node, issues}
      end)

    Enum.sort_by(issues, & &1.line_no)
  end

  defp boolean_issue(name, :boolean, meta, issue_meta, allowed) when is_atom(name) do
    if prefixed?(name, allowed) do
      []
    else
      [issue(issue_meta, meta, name)]
    end
  end

  defp boolean_issue(_name, _type, _meta, _issue_meta, _allowed), do: []

  defp type_issues(value, allowed, issue_meta) do
    {_value, issues} =
      Macro.prewalk(value, [], fn
        {:%{}, meta, pairs} = node, acc when is_list(pairs) ->
          {node, boolean_key_issues(pairs, meta, allowed, issue_meta) ++ acc}

        node, acc ->
          {node, acc}
      end)

    issues
  end

  defp boolean_key_issues(pairs, meta, allowed, issue_meta) do
    for {name, type} <- pairs,
        is_atom(name),
        boolean_type?(type),
        not prefixed?(name, allowed),
        do: issue(issue_meta, meta, name)
  end

  defp property_issues(pairs, meta, issue_meta, allowed) do
    for {name, value} <- pairs,
        is_atom(name),
        boolean_schema?(value),
        not prefixed?(name, allowed),
        do: issue(issue_meta, meta, name)
  end

  defp boolean_schema?({:%, _meta, [alias, {:%{}, _meta2, struct_kv}]})
       when is_list(struct_kv) do
    schema_alias?(alias) and Keyword.get(struct_kv, :type) == :boolean
  end

  defp boolean_schema?(_value), do: false

  defp schema_alias?({:__aliases__, _meta, [:Schema]}), do: true
  defp schema_alias?({:__aliases__, _meta, [:OpenApiSpex, :Schema]}), do: true
  defp schema_alias?(_other), do: false

  defp boolean_type?({:boolean, _meta, []}), do: true
  defp boolean_type?({:|, _meta, [{:boolean, _meta2, []}, nil]}), do: true
  defp boolean_type?({:|, _meta, [nil, {:boolean, _meta2, []}]}), do: true
  defp boolean_type?(_other), do: false

  defp prefixed?(name, allowed) when is_atom(name) do
    name = Atom.to_string(name)
    Enum.any?(allowed, &String.starts_with?(name, &1))
  end

  defp issue(issue_meta, meta, name) do
    format_issue(issue_meta,
      message:
        "Name the boolean field `is_#{Atom.to_string(name)}`: with the `is_` prefix a flag cannot be misread for a thing.",
      trigger: Atom.to_string(name),
      line_no: meta[:line]
    )
  end
end
