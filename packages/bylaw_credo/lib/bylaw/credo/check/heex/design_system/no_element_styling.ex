defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling do
  @moduledoc """
  Forbids class and style attributes on raw HTML elements, so templates can
  only compose components.

  ## Examples

  Avoid:

      ~H\"\"\"
      <div class="flex gap-2 rounded border p-4">
        <p style="color: red">Archived</p>
      </div>
      \"\"\"

  Prefer:

      ~H\"\"\"
      <.card>
        <.banner tone="warning">Archived</.banner>
      </.card>
      \"\"\"

  A page that can style an element can rebuild a component by hand, and nothing
  fails when it does, so the same card, button or tag ends up drawn in several
  places that drift apart. A page that cannot style anything can only compose
  components, so a new look has to be added to the component library first.

  Every `class` and `style` attribute on a raw HTML element is reported,
  whether its value is a literal or an expression. Component tags are left
  alone (`Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass` covers their
  class attribute), and so are slot tags, raw elements without styling, and
  other attributes such as `id`, `href` or `data-*`. Run the check on the code
  that uses the component library and exclude the library's own files with
  Credo's per-check `files` param, which Credo's runner applies before running
  the check. The check cannot tell a good component from a poor or duplicate
  one. Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  A codebase that already has styled pages can adopt the check with
  `:ceilings`, which lets each not-yet-converted file keep the styling
  attributes it has today and no more, and can only go down. A file at its
  ceiling reports nothing. Above it, every styling attribute is reported.
  Below it, the check asks for the ceiling to be lowered, and at zero with an
  entry, for the entry to be removed.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling,
           [
             files: %{excluded: ["lib/my_app_web/components/"]},
             ceilings: %{"lib/my_app_web/live/account_live.ex" => 12}
           ]}
        ]
      }
    ]
  }
  ```

  - `:attributes` - Attribute names that count as styling (default: `["class", "style"]`).
  - `:ceilings` - A map from a file path to how many styling attributes that file may still have (default: `%{}`). A path matches a file when it equals the path Credo reports for it, which is relative to the directory Credo runs in, such as `lib/my_app_web/live/account_live.ex`; a leading `./` is ignored. A file without an entry has a ceiling of zero. A value that is not a non-negative integer, or a key that is not a string, raises an `ArgumentError`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling,
           [files: %{excluded: ["lib/my_app_web/components/"]}]}
        ]
      }
    ]
  }
  ```

  ## Notes

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:web, :design_system],
    param_defaults: [attributes: ~w(class style), ceilings: %{}],
    explanations: [
      check: @moduledoc,
      params: [
        attributes: "Attribute names that count as styling (default: class and style).",
        ceilings:
          "A map from a file path to how many styling attributes that file may still have (default: none)."
      ]
    ]

  alias Bylaw.Credo.Heex

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    attributes = attributes(params)
    ceilings = ceilings(params)

    styled =
      source_file
      |> Heex.templates()
      |> Enum.flat_map(&Heex.tags/1)
      |> Enum.flat_map(&styling_attrs(&1, attributes))

    ceiling = Map.get(ceilings, normalize_path(source_file.filename), 0)

    issues(issue_meta, styled, ceiling)
  end

  defp issues(issue_meta, styled, ceiling) do
    count = Enum.count(styled)

    cond do
      count > ceiling ->
        Enum.map(styled, &element_issue(issue_meta, &1))

      count == ceiling ->
        []

      count == 0 ->
        [
          file_issue(
            issue_meta,
            "This file has no styling attributes left. Remove its ceiling from .credo.exs."
          )
        ]

      true ->
        [
          file_issue(
            issue_meta,
            "This file has #{count} styling #{pluralize(count)} and its ceiling is #{ceiling}. Lower the ceiling to #{count} in .credo.exs."
          )
        ]
    end
  end

  defp styling_attrs(%Heex.Tag{type: :tag, attrs: attrs} = tag, attributes) do
    attrs
    |> Enum.filter(&styling_attr?(&1, attributes))
    |> Enum.map(&Map.put(&1, :tag, tag))
  end

  defp styling_attrs(_tag, _attributes), do: []

  defp styling_attr?(%{name: name}, attributes) when is_binary(name) do
    String.downcase(name) in attributes
  end

  defp styling_attr?(_attr, _attributes), do: false

  defp element_issue(issue_meta, %{tag: %Heex.Tag{} = tag, name: name} = attr) do
    format_issue(
      issue_meta,
      message:
        "#{name} on <#{tag.name}>: pages don't style elements. Use a component from the component library, or add one there first.",
      trigger: name,
      line_no: attr.line || tag.line,
      column: attr.column || tag.column
    )
  end

  defp file_issue(issue_meta, message) do
    format_issue(issue_meta, message: message, line_no: 1)
  end

  defp attributes(params) do
    names = Params.get(params, :attributes, __MODULE__)
    Enum.map(names, &String.downcase/1)
  end

  defp ceilings(params) do
    ceilings = Params.get(params, :ceilings, __MODULE__)
    validate_ceilings!(ceilings)
  end

  defp pluralize(1), do: "attribute"
  defp pluralize(_count), do: "attributes"

  defp validate_ceilings!(ceilings) when is_map(ceilings) do
    Map.new(ceilings, fn
      {path, count} when is_binary(path) and is_integer(count) and count >= 0 ->
        {normalize_path(path), count}

      {path, count} ->
        raise ArgumentError,
              "NoElementStyling :ceilings must map a file path to a non-negative integer, got #{inspect(path)} => #{inspect(count)}"
    end)
  end

  defp validate_ceilings!(other) do
    raise ArgumentError,
          "NoElementStyling :ceilings must be a map from file path to a non-negative integer, got #{inspect(other)}"
  end

  defp normalize_path("./" <> path), do: normalize_path(path)
  defp normalize_path(path), do: path
end
