defmodule Bylaw.Credo.Check.HEEx.DesignSystem.PreferComponentOverTagTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.PreferComponentOverTag

  @tags [button: ".button", input: ".input"]

  test "reports a raw tag that has a configured component" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferComponentOverTag, tags: @tags)
    |> assert_issue(%{
      line_no: 4,
      column: 5,
      trigger: "<button",
      message:
        "Use the <.button> component instead of a raw <button> tag, so the design system owns its markup."
    })
  end

  test "reports a self-closing raw tag once" do
    """
    <input type="text" name="title" />
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: @tags)
    |> assert_issue(%{line_no: 1, column: 1, trigger: "<input"})
  end

  test "reports every configured raw tag in a template" do
    """
    <form>
      <input name="title" />
      <button type="submit">Save</button>
      <button type="button">Cancel</button>
    </form>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: @tags)
    |> assert_issues(fn issues -> assert Enum.count(issues) == 3 end)
  end

  test "ignores raw tags that have no configured component" do
    """
    <div><select name="kind"></select><a href="/">Home</a></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: @tags)
    |> refute_issues()
  end

  test "ignores the preferred components themselves" do
    """
    <.button type="submit">Save</.button>
    <.input field={@form[:title]} />
    <CoreComponents.button>Save</CoreComponents.button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: @tags)
    |> refute_issues()
  end

  test "ignores slots named like a configured tag" do
    """
    <.toolbar>
      <:button>Save</:button>
    </.toolbar>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: @tags)
    |> refute_issues()
  end

  test "accepts string keys and component names without a leading dot" do
    """
    <button type="button">Save</button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: %{"button" => "button"})
    |> assert_issue(%{
      message:
        "Use the <.button> component instead of a raw <button> tag, so the design system owns its markup."
    })
  end

  test "names a remote component as written" do
    """
    <button type="button">Save</button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag, tags: [button: "UI.button"])
    |> assert_issue(%{
      message:
        "Use the <UI.button> component instead of a raw <button> tag, so the design system owns its markup."
    })
  end

  test "reports nothing without configured tags" do
    """
    <button type="button">Save</button>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(PreferComponentOverTag)
    |> refute_issues()
  end
end
