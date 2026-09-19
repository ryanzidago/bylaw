defmodule Bylaw.Credo.Check.Ecto.TypeBeforeSchema do
  @moduledoc """
  Requires `@type`, `@typep` and `@opaque` definitions to appear before an Ecto
  `schema` or `embedded_schema` block in the same module.

  ## Examples

  Avoid:

  ```elixir
  defmodule MyApp.User do
    use MyApp.Schema

    schema "users" do
      field :name, :string
    end

    @type t :: %__MODULE__{name: String.t() | nil}
  end
  ```

  Prefer:

  ```elixir
  defmodule MyApp.User do
    use MyApp.Schema

    @type t :: %__MODULE__{name: String.t() | nil}

    schema "users" do
      field :name, :string
    end
  end
  ```

  Declaring the types first gives every schema module the same reading order:
  the struct's contract, then the fields that back it, then the functions that
  work on it.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.TypeBeforeSchema, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    tags: [:readability, :database],
    explanations: [check: @moduledoc]

  @schema_macros [:schema, :embedded_schema]
  @type_attributes [:type, :typep, :opaque]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:defmodule, _meta, [_name, [do: body]]} = node, issues, issue_meta) do
    {node, issues ++ issues_for_body(body, issue_meta)}
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  defp issues_for_body(body, issue_meta) do
    body
    |> body_expressions()
    |> Enum.drop_while(&(not schema_block?(&1)))
    |> Enum.filter(&type_attribute?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp body_expressions({:__block__, _meta, expressions}), do: expressions
  defp body_expressions(expression), do: [expression]

  defp schema_block?({name, _meta, args}) when name in @schema_macros and is_list(args) do
    match?([do: _body], List.last(args))
  end

  defp schema_block?(_expression), do: false

  defp type_attribute?({:@, _meta, [{kind, _attribute_meta, [_definition]}]}),
    do: kind in @type_attributes

  defp type_attribute?(_expression), do: false

  defp issue_for(issue_meta, {:@, meta, [{kind, _attribute_meta, [definition]}]}) do
    format_issue(
      issue_meta,
      message:
        "`@#{kind}` should appear before the Ecto schema block so the module reads type, then schema, then functions.",
      trigger: type_name(definition),
      line_no: meta[:line]
    )
  end

  defp type_name({:"::", _meta, [head, _body]}), do: type_name(head)
  defp type_name({name, _meta, _args}) when is_atom(name), do: Atom.to_string(name)
end
