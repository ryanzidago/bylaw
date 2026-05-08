defmodule Bylaw.Credo.Check.HEEx.DesignSystem.AllowedClassesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.AllowedClasses

  @rules [
    [prefix: "duration-", allowed: ~w(duration-150)],
    [prefix: "delay-", allowed: ~w(delay-75 delay-150)],
    [prefix: "rounded-", allowed: ~w(rounded-none rounded-sm rounded rounded-md)],
    [prefix: "shadow", allowed: ~w(shadow-none shadow-sm shadow shadow-md)]
  ]

  test "flags a disallowed class matching a prefix" do
    """
    <div class="duration-300"></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{
      line_no: 1,
      trigger: "duration-300",
      message:
        ~s(Class "duration-300" is outside the configured "duration-" design-system scale. Allowed: duration-150.)
    })
  end

  test "allows an allowed class matching a prefix" do
    """
    <div class="duration-150 rounded-md shadow-sm"></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> refute_issues()
  end

  test "ignores unrelated classes" do
    """
    <div class="flex items-center text-sm"></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> refute_issues()
  end

  test "handles multiple rules" do
    """
    <div class="duration-150 delay-300 rounded-lg shadow-lg"></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 1, trigger: "delay-300"},
      %{line_no: 1, trigger: "rounded-lg"},
      %{line_no: 1, trigger: "shadow-lg"}
    ])
  end

  test "returns no issues when no rules are configured" do
    """
    <div class="duration-300 rounded-lg"></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses)
    |> refute_issues()
  end

  test "ignores dynamic-only class values" do
    """
    <div class={@class}></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> refute_issues()
  end

  test "flags static string class expressions" do
    """
    <div class={"duration-300"}></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{line_no: 1, trigger: "duration-300"})
  end

  test "flags static class list entries while ignoring dynamic entries" do
    """
    <div class={["rounded-lg", @class, "duration-150"]}></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{line_no: 1, trigger: "rounded-lg"})
  end

  test "flags static sigil word class expressions" do
    """
    <div class={~w(shadow-lg duration-150)}></div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{line_no: 1, trigger: "shadow-lg"})
  end

  test "flags disallowed classes on local components" do
    """
    <.button class="duration-300" />
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{line_no: 1, trigger: "duration-300"})
  end

  test "flags disallowed classes on remote components" do
    """
    <CoreComponents.button class="rounded-lg" />
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{line_no: 1, trigger: "rounded-lg"})
  end

  test "reports multiple violations when present" do
    """
    <div class="duration-300 delay-500"></div>
    <section class="rounded-lg"></section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 1, trigger: "duration-300"},
      %{line_no: 1, trigger: "delay-500"},
      %{line_no: 2, trigger: "rounded-lg"}
    ])
  end

  test "works for embedded H templates" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="duration-300"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(AllowedClasses, rules: @rules)
    |> assert_issue(%{line_no: 4, trigger: "duration-300"})
  end
end
