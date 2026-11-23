defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoHexColorTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoHexColor

  @message "Use currentColor or a named CSS class that uses a colour token instead of a hex colour."

  defp run_template(template, params \\ []) do
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
    |> run_check(NoHexColor, params)
  end

  test "reports a hex colour in fill and stroke" do
    ~s|<svg fill="#0a0a0a"><path stroke="#fff" /></svg>|
    |> run_template()
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "fill", message: ~r/#{Regex.escape(@message)} Colour: "#0a0a0a"\./},
      %{trigger: "stroke", message: ~r/Colour: "#fff"\./}
    ])
  end

  test "reports a hex colour in a string literal of a dynamic attribute" do
    ~S|<path fill={if @on, do: "#16a34a", else: "currentColor"} />|
    |> run_template()
    |> assert_issue(%{message: ~r/"#16a34a"/})
  end

  test "reports a hex colour carried in a custom property" do
    ~s|<div style="--accent: #ff0000"></div>|
    |> run_template()
    |> assert_issue()
  end

  test "reports an eight digit hex colour" do
    ~s|<rect fill="#ff000080" />|
    |> run_template()
    |> assert_issue()
  end

  test "allows currentColor, none and a url" do
    ~s|<svg fill="none" stroke="currentColor"><path fill="url(#grad)" /></svg>|
    |> run_template()
    |> refute_issues()
  end

  test "ignores anchors and text that look like hex" do
    ~s|<a href="#add" id="#fed">Order #1362</a>|
    |> run_template()
    |> refute_issues()
  end

  test "reads the attributes it is given" do
    ~s|<div data-color="#fff" fill="#fff"></div>|
    |> run_template(attributes: ["data-color"])
    |> assert_issue(%{trigger: "data-color"})
  end

  test "checks standalone heex files" do
    ~s|<path fill="#fff" />|
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoHexColor)
    |> assert_issue()
  end
end
