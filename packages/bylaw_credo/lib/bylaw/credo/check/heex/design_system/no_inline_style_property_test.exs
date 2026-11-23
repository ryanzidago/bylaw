defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStylePropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle

  property "reports a style exactly when one of its declarations is not a custom property" do
    check all(declarations <- list_of(declaration(), min_length: 1, max_length: 6)) do
      style = Enum.map_join(declarations, "; ", &elem(&1, 0))
      expected = Enum.count(declarations, fn {_text, custom?} -> not custom? end) > 0

      issues =
        ~s(<div style="#{style}"></div>)
        |> Credo.SourceFile.parse("lib/example/index.html.heex")
        |> run_check(NoInlineStyle)

      assert length(issues) == if(expected, do: 1, else: 0)
    end
  end

  defp declaration do
    one_of([
      map(member_of(~w|--progress:40% --gap:3 --hero-image:url(/a.png)|), &{&1, true}),
      map(member_of(~w|color:red padding:13px width:10px background:#fff|), &{&1, false})
    ])
  end
end
