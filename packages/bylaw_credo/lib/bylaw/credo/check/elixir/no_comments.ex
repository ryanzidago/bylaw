defmodule Bylaw.Credo.Check.Elixir.NoComments do
  @moduledoc """
  Forbid code comments in Elixir files and HEEx templates.

  ## Examples

  Avoid:

        defmodule Cart do
          # Adds the item and recomputes the total.
          def add(cart, item), do: recompute(%{cart | items: [item | cart.items]})
        end

        ~H\"\"\"
        <%!-- The checkout button --%>
        <.button type="submit">{gettext("Pay")}</.button>
        \"\"\"

  Prefer:

        defmodule Cart do
          @doc "Adds the item and recomputes the total."
          def add(cart, item), do: recompute(%{cart | items: [item | cart.items]})
        end

        ~H\"\"\"
        <.button type="submit">{gettext("Pay")}</.button>
        \"\"\"


  Code says what it does. A reason that must outlive the change belongs in
  `@moduledoc`, `@doc` or `@typedoc`, where it is rendered with the docs and
  kept next to the code it explains; version control keeps the rest. Comments
  are not checked by the compiler, so they drift out of date silently.

  The check reports `#` comments, on their own line or at the end of a line,
  and `<%!-- … --%>` and `<!-- … -->` comments inside `~H` sigils and
  `.html.heex` templates. It reads comments from the Elixir parser, so a `#`
  inside a string, heredoc, charlist or sigil is not a comment. It allows tool
  directives that start with one of `:allowed_directives`, such as
  `# credo:disable-for-next-line`, and a shebang (`#!`) on the first line.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoComments,
           [
             allowed_directives: ["credo:", "excellent_migrations:"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:allowed_directives` - Comment prefixes that mark tool directives, which
    are allowed. A comment is allowed when its text after `#` and any
    whitespace starts with one of them. Defaults to `["credo:"]`.

  Use Credo's per-check `files: %{excluded: [...]}` option to skip files where
  comments are still allowed.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoComments, []}
        ]
      }
    ]
  }
  ```

  ## Notes

  Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [allowed_directives: ["credo:"]],
    explanations: [
      check: @moduledoc,
      params: [
        allowed_directives:
          "Comment prefixes that mark allowed tool directives, matched after `#` and whitespace."
      ]
    ]

  alias Bylaw.Credo.Heex

  @heex_comment ~r/<%!--.*?--%>|<!--.*?-->/s
  @message "Remove the comment. Put a lasting reason in @moduledoc, @doc or @typedoc, or drop it."

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed_directives = Params.get(params, :allowed_directives, __MODULE__)

    source_file
    |> comments(allowed_directives)
    |> Enum.sort()
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp comments(source_file, allowed_directives) do
    hash_comments =
      if String.ends_with?(source_file.filename, ".heex") do
        []
      else
        source_file
        |> Credo.SourceFile.source()
        |> hash_comments(allowed_directives)
      end

    heex_comments =
      source_file
      |> Heex.templates()
      |> Enum.flat_map(&template_comments/1)

    hash_comments ++ heex_comments
  end

  defp hash_comments(source, allowed_directives) do
    case Code.string_to_quoted_with_comments(source) do
      {:ok, _ast, comments} ->
        comments
        |> Enum.reject(&allowed?(&1, allowed_directives))
        |> Enum.map(&{&1.line, &1.text})

      {:error, _reason} ->
        []
    end
  end

  defp allowed?(%{line: line, text: text}, allowed_directives) do
    shebang? = line == 1 and String.starts_with?(text, "#!")

    directive =
      text
      |> String.trim_leading("#")
      |> String.trim_leading()

    shebang? or String.starts_with?(directive, allowed_directives)
  end

  defp template_comments(%Heex.Template{source: source, line: first_line}) do
    @heex_comment
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      newlines_before =
        source
        |> binary_part(0, offset)
        |> String.split("\n")
        |> Enum.count()

      {first_line + newlines_before - 1, binary_part(source, offset, length)}
    end)
  end

  defp issue_for(issue_meta, {line_no, text}) do
    format_issue(issue_meta, message: @message, trigger: text, line_no: line_no)
  end
end
