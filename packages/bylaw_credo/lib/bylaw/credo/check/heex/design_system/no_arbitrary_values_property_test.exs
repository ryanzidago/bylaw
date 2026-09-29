defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValuesPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValues

  property "reports exactly the classes whose utility carries an arbitrary value" do
    check all(classes <- list_of(class(), max_length: 12)) do
      expected_issue_count = Enum.count(classes, fn {_class, arbitrary?} -> arbitrary? end)

      ~s(<div class="#{Enum.map_join(classes, " ", &elem(&1, 0))}"></div>)
      |> Credo.SourceFile.parse("lib/example/index.html.heex")
      |> run_check(NoArbitraryValues)
      |> assert_issues(expected_issue_count)
    end
  end

  defp class do
    gen all(
          variants <- list_of(variant(), max_length: 3),
          {utility, arbitrary?} <- utility()
        ) do
      {Enum.map_join(variants, &(&1 <> ":")) <> utility, arbitrary?}
    end
  end

  defp variant do
    member_of(~w|hover md dark before has-[textarea:focus] data-[state=open] [&>*] group-has-[x]|)
  end

  defp utility do
    one_of([
      map(member_of(~w|p-4 bg-fill text-sm grid-cols-2 w-(--measure) -mt-2 !w-4|), &{&1, false}),
      map(
        member_of(~w|w-[3px] -left-[42px] !h-[30px] grid-cols-[1fr_auto] [mask-type:alpha]|),
        &{&1, true}
      )
    ])
  end
end
