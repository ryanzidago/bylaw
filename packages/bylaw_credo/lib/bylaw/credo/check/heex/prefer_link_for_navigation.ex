defmodule Bylaw.Credo.Check.HEEx.PreferLinkForNavigation do
  @moduledoc """
  Prefers link semantics over button semantics for durable HEEx/HTML navigation.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <button phx-click={JS.navigate(~p"/settings")}>Settings</button>
        <div phx-click={JS.patch(~p"/users")}>Users</div>
        <.button phx-click={JS.navigate(~p"/billing")}>Billing</.button>
        <button phx-click={Phoenix.LiveView.JS.patch("/users")}>Users</button>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <a href={~p"/settings"}>Settings</a>
        <.link patch={~p"/users"}>Users</.link>
        <.link navigate={~p"/billing"}>Billing</.link>
        \"\"\"

  ## Notes

  Embedded `~H` templates in `.ex` and `.exs` files are checked by Credo's normal source traversal. Standalone `.html.heex` templates are checked when `Bylaw.Credo.Plugin.HEExSources` is enabled in `.credo.exs`.

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.

  This check uses static HEEx token analysis, so it reports only patterns visible in the template source.

  This check enforces link semantics for durable navigation so users keep native browser behaviors such as opening a destination in a new tab, copying the URL, and using standard link interactions.

  This check reports non-link HEEx tags and components whose `phx-click`
  expression contains an explicit `JS.navigate/1-3`, `JS.patch/1-3`,
  `Phoenix.LiveView.JS.navigate/1-3`, or `Phoenix.LiveView.JS.patch/1-3` call.
  Native `<a>` tags and the standard `<.link>` component are allowed here as
  link primitives. The check does not attempt to infer event-name strings or
  dynamic expressions that do not contain one of those explicit navigation
  calls.

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
          {Bylaw.Credo.Check.HEEx.PreferLinkForNavigation, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Use a link for navigation so users can open it in a new tab, copy the URL, and get native browser link behavior."
  @navigation_commands [:navigate, :patch]
  @navigation_modules [[:JS], [:Phoenix, :LiveView, :JS]]

  @doc false
  @impl Credo.Check
  @spec run(Credo.SourceFile.t(), keyword()) :: list(Credo.Issue.t())
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&navigation_tag?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp navigation_tag?(%Heex.Tag{} = tag) do
    not link_primitive?(tag) and
      tag
      |> attr_value("phx-click")
      |> navigation_command_expr?()
  end

  defp link_primitive?(%Heex.Tag{type: :tag, name: "a"}), do: true
  defp link_primitive?(%Heex.Tag{type: :local_component, name: "link"}), do: true
  defp link_primitive?(_tag), do: false

  defp attr_value(%Heex.Tag{attrs: attrs}, name) do
    case Enum.find(attrs, &(&1.name == name)) do
      nil -> nil
      attr -> attr.value
    end
  end

  defp navigation_command_expr?({:expr, expr, _meta}) when is_binary(expr) do
    case Code.string_to_quoted(expr, columns: true) do
      {:ok, ast} -> navigation_command_ast?(ast)
      _error -> false
    end
  end

  defp navigation_command_expr?(_value), do: false

  defp navigation_command_ast?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? ->
        {node, found? or navigation_command_call?(node)}
      end)

    found?
  end

  defp navigation_command_call?(
         {{:., _meta, [{:__aliases__, _aliases_meta, module}, command]}, _call_meta, arguments}
       )
       when command in @navigation_commands and module in @navigation_modules and
              is_list(arguments) and arguments != [] do
    true
  end

  defp navigation_command_call?(_ast), do: false

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: trigger_for(tag),
      line_no: tag.line,
      column: tag.column
    )
  end

  defp trigger_for(%Heex.Tag{type: :local_component, name: name}), do: "<.#{name}"
  defp trigger_for(%Heex.Tag{name: name}), do: "<#{name}"
end
