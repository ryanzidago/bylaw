defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValuesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValues

  @message "Use a design-system token or a named CSS rule instead of an arbitrary Tailwind value."

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
    |> run_check(NoArbitraryValues)
  end

  test "reports an arbitrary value in a static class" do
    ~s|<div class="w-[430px]"></div>|
    |> run_template()
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: ~r/#{Regex.escape(@message)} Arbitrary value: "w-\[430px\]"\./
    })
  end

  test "reports each arbitrary value once" do
    ~s|<div class="grid grid-cols-[34px_minmax(0,1fr)] shadow-[0_1px_0_var(--x)] p-4"></div>|
    |> run_template()
    |> assert_issues(2)
    |> assert_issues_match([
      %{message: ~r/Arbitrary value: "grid-cols-\[34px_minmax\(0,1fr\)\]"/},
      %{message: ~r/Arbitrary value: "shadow-\[0_1px_0_var\(--x\)\]"/}
    ])
  end

  test "reports negative, important and variant-prefixed arbitrary values" do
    ~s|<div class="-left-[42px] !w-[3px] before:w-[42px] md:hover:h-[30px]"></div>|
    |> run_template()
    |> assert_issues(4)
  end

  test "reports arbitrary properties" do
    ~s|<div class="[mask-type:luminance] hover:[mask-type:alpha]"></div>|
    |> run_template()
    |> assert_issues(2)
  end

  test "allows arbitrary variants" do
    ~s|<div class="has-[textarea:not(:placeholder-shown)]:bg-fill data-[state=open]:flex [&>*]:p-2 group-has-[x]:hidden"></div>|
    |> run_template()
    |> refute_issues()
  end

  test "reports an arbitrary value behind an arbitrary variant" do
    ~s|<div class="[&>*]:w-[3px]"></div>|
    |> run_template()
    |> assert_issue(%{message: ~r/Arbitrary value: "\[&>\*\]:w-\[3px\]"/})
  end

  test "allows CSS variable shorthand and theme utilities" do
    ~s|<div class="w-(--measure) bg-fill text-sm grid-cols-2"></div>|
    |> run_template()
    |> refute_issues()
  end

  test "reports arbitrary values in string literals of a dynamic class" do
    ~s|<div class={["p-4 w-[3px]", @open && "h-[30px]", if(@wide, do: "max-w-[80ch]", else: "max-w-md")]}></div>|
    |> run_template()
    |> assert_issues(3)
    |> assert_issues_match([
      %{message: ~r/"w-\[3px\]"/},
      %{message: ~r/"h-\[30px\]"/},
      %{message: ~r/"max-w-\[80ch\]"/}
    ])
  end

  test "reports arbitrary values in the literal parts of an interpolated class" do
    ~S|<div class={"top-[6px] #{@extra}"}></div>|
    |> run_template()
    |> assert_issue(%{message: ~r/"top-\[6px\]"/})
  end

  test "reports arbitrary values on component tags" do
    ~s|<.button class="w-[3px]">Save</.button>|
    |> run_template()
    |> assert_issue(%{trigger: "class"})
  end

  test "ignores arbitrary values outside the class attribute" do
    ~s|<div data-size="w-[3px]" title={"h-[30px]"}></div>|
    |> run_template()
    |> refute_issues()
  end

  test "reports arbitrary values in standalone HEEx templates" do
    ~s|<div class="w-[3px]"></div>|
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoArbitraryValues)
    |> assert_issue()
  end
end
