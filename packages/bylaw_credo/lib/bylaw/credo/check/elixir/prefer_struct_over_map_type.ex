defmodule Bylaw.Credo.Check.Elixir.PreferStructOverMapType do
  @moduledoc """
  Prefer a struct over a fixed-shape map type such as `%{id: integer(), name: String.t()}`.

  ## Examples

  Avoid:

        @type user :: %{id: integer(), name: String.t()}

        @spec rename(user :: %{id: integer(), name: String.t()}, name :: String.t()) ::
                %{id: integer(), name: String.t()}

  Prefer:

        defmodule User do
          @enforce_keys [:id, :name]
          defstruct [:id, :name]

          @type t :: %__MODULE__{id: integer(), name: String.t()}
        end

        @spec rename(user :: User.t(), name :: String.t()) :: User.t()

  A map type whose keys are all literal atoms describes a record with a fixed
  shape, and a struct says the same thing in a way the compiler and tools can
  enforce. Building `%User{}` with a missing `@enforce_keys` key or an unknown
  key fails at compile time, while a plain map with a typo in a key is only
  caught at runtime, if at all. Functions can pattern match on the struct
  name (`%User{} = user`), so a different map with the same keys cannot pass
  by accident. Type checkers, including Elixir's own, know every field of a
  struct and its type from the struct definition, so they can report a wrong
  field access without relying on a typespec repeated at every call site.

  The check reports a map type in `@type`, `@typep`, `@opaque`, `@spec`,
  `@callback` and `@macrocallback` when every key is a literal atom (written
  as `key: type`, `:key => type`, `required(:key) => type` or
  `optional(:key) => type`) and it has at least `:min_keys` keys. A map with a
  non-literal key, such as `%{optional(atom()) => term()}` or
  `%{String.t() => integer()}`, is open-ended and is not reported, and neither
  are struct types such as `%__MODULE__{}` or `%User{id: integer()}`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.PreferStructOverMapType,
           [
             min_keys: 3,
             excluded_paths: ["test/support/", ~r"/generated/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:min_keys` - The smallest number of keys a closed map type needs before
    it is reported. Defaults to `2`.
  - `:excluded_paths` - List of path substrings or regexes to exclude from
    this check. Defaults to `[]`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.PreferStructOverMapType, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :normal,
    category: :design,
    tags: [:readability],
    param_defaults: [min_keys: 2, excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        min_keys: "The smallest number of keys a closed map type needs before it is reported.",
        excluded_paths: "List of path substrings or regexes to exclude from this check."
      ]
    ]

  alias Credo.SourceFile

  @typespec_attributes [:type, :typep, :opaque, :spec, :callback, :macrocallback]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      min_keys = Params.get(params, :min_keys, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&walk(&1, &2, issue_meta, min_keys))
      |> Enum.reverse()
    end
  end

  defp walk(
         {:@, _meta, [{attribute, _attribute_meta, arguments}]} = ast,
         issues,
         issue_meta,
         min_keys
       )
       when attribute in @typespec_attributes and is_list(arguments) do
    issues = Enum.reduce(arguments, issues, &traverse_type(&1, &2, issue_meta, min_keys))
    {ast, issues}
  end

  defp walk(ast, issues, _issue_meta, _min_keys), do: {ast, issues}

  defp traverse_type(
         {:%, _meta, [module_ast, {:%{}, _map_meta, fields}]},
         issues,
         issue_meta,
         min_keys
       )
       when is_list(fields) do
    issues = traverse_type(module_ast, issues, issue_meta, min_keys)
    Enum.reduce(fields, issues, &traverse_field(&1, &2, issue_meta, min_keys))
  end

  defp traverse_type({:%{}, meta, fields} = ast, issues, issue_meta, min_keys)
       when is_list(fields) do
    issues =
      if closed?(fields) and Enum.count(fields) >= min_keys do
        [issue_for(issue_meta, ast, meta[:line]) | issues]
      else
        issues
      end

    Enum.reduce(fields, issues, &traverse_field(&1, &2, issue_meta, min_keys))
  end

  defp traverse_type(list, issues, issue_meta, min_keys) when is_list(list) do
    Enum.reduce(list, issues, &traverse_type(&1, &2, issue_meta, min_keys))
  end

  defp traverse_type({left, right}, issues, issue_meta, min_keys) do
    issues = traverse_type(left, issues, issue_meta, min_keys)
    traverse_type(right, issues, issue_meta, min_keys)
  end

  defp traverse_type({_name, _meta, arguments}, issues, issue_meta, min_keys)
       when is_list(arguments) do
    traverse_type(arguments, issues, issue_meta, min_keys)
  end

  defp traverse_type(_ast, issues, _issue_meta, _min_keys), do: issues

  defp traverse_field({_key, value}, issues, issue_meta, min_keys) do
    traverse_type(value, issues, issue_meta, min_keys)
  end

  defp traverse_field(_field, issues, _issue_meta, _min_keys), do: issues

  defp closed?(fields), do: Enum.all?(fields, &literal_atom_key?/1)

  defp literal_atom_key?({key, _value}) when is_atom(key), do: true

  defp literal_atom_key?({{marker, _meta, [key]}, _value})
       when marker in [:required, :optional] and is_atom(key),
       do: true

  defp literal_atom_key?(_field), do: false

  defp issue_for(issue_meta, ast, line_no) do
    format_issue(
      issue_meta,
      message:
        "Prefer a struct over a fixed-shape map type. Define a struct with " <>
          "`@enforce_keys` and a `t()` type, and use `t()` here.",
      trigger: Macro.to_string(ast),
      line_no: line_no
    )
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end
end
