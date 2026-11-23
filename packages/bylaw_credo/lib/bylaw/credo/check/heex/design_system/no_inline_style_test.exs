defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyleTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle

  @message "Use a named CSS class that uses design-system tokens instead of an inline style."

  defp run_template(template) do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        #{template}
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoInlineStyle)
  end

  test "reports a static style that sets a property" do
    ~s|<div style="padding: 13px"></div>|
    |> run_template()
    |> assert_issue(%{line_no: 4, trigger: "style", message: ~r/#{Regex.escape(@message)}/})
  end

  test "reports a dynamic style that sets a property" do
    ~S|<div style={"width: #{@width}px"}></div>|
    |> run_template()
    |> assert_issue()
  end

  test "reports a style that mixes a custom property with a property" do
    ~s|<div style="--x: 1; color: red"></div>|
    |> run_template()
    |> assert_issue()
  end

  test "reports a style it cannot read" do
    ~s|<div style={@style}></div>|
    |> run_template()
    |> assert_issue()
  end

  test "reports a style on a component call" do
    ~s|<.card style="margin: 0"></.card>|
    |> run_template()
    |> assert_issue()
  end

  test "reports a property whose name is interpolated" do
    ~S|<div style={"#{@name}: 1"}></div>|
    |> run_template()
    |> assert_issue()
  end

  test "allows a static style that only sets custom properties" do
    ~s|<div style="--progress: 40%; --gap: 3"></div>|
    |> run_template()
    |> refute_issues()
  end

  test "allows an interpolated value in a custom property" do
    ~S|<div style={"--progress: #{@percent}%"}></div>|
    |> run_template()
    |> refute_issues()
  end

  test "allows an element with no style" do
    ~s|<div class="card" data-style="x"></div>|
    |> run_template()
    |> refute_issues()
  end

  test "checks standalone heex files" do
    ~s|<div style="color: red"></div>|
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoInlineStyle)
    |> assert_issue()
  end
end
