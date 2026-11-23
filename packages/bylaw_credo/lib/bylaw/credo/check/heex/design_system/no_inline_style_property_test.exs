defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStylePropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle

  property "reports a style exactly when one of its declarations is not a custom property" do
    check all(declarations <- list_of(declaration(), min_length: 1, max_length: 6)) do
      style = Enum.map_join(declarations, "; ", &elem(&1, 0))
      expected = not Enum.all?(declarations, fn {_text, custom?} -> custom? end)

      issues =
        ~s(<div style="#{style}"></div>)
        |> Credo.SourceFile.parse("lib/example/index.html.heex")
        |> run_check(NoInlineStyle)

      assert Enum.count(issues) == to_count(expected)
    end
  end

  defp to_count(true), do: 1
  defp to_count(false), do: 0

  defp declaration do
    one_of([
      map(member_of(~w|--progress:40% --gap:3 --hero-image:url(/a.png)|), &{&1, true}),
      map(member_of(~w|color:red padding:13px width:10px background:#fff|), &{&1, false})
    ])
  end
end
