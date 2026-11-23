defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStylingPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling

  @path "lib/example/index.html.heex"

  property "every raw element carrying a styling attribute reports one issue per attribute" do
    check all(tags <- list_of(tag(), max_length: 12)) do
      expected =
        tags
        |> Enum.filter(fn {kind, _attrs} -> kind == :html end)
        |> Enum.map(fn {_kind, attrs} -> Enum.count(attrs) end)
        |> Enum.sum()

      tags
      |> template()
      |> Credo.SourceFile.parse(@path)
      |> run_check(NoElementStyling)
      |> assert_issues(expected)
    end
  end

  property "a ceiling equal to the count reports nothing and any other ceiling reports something" do
    check all(tags <- list_of(tag(), max_length: 12), ceiling <- integer(0..30)) do
      count =
        tags
        |> Enum.filter(fn {kind, _attrs} -> kind == :html end)
        |> Enum.map(fn {_kind, attrs} -> Enum.count(attrs) end)
        |> Enum.sum()

      issues =
        tags
        |> template()
        |> Credo.SourceFile.parse(@path)
        |> run_check(NoElementStyling, ceilings: %{@path => ceiling})

      if count == ceiling or (count == 0 and ceiling == 0) do
        assert issues == []
      else
        assert issues != []
      end
    end
  end

  defp tag do
    gen all(
          kind <- member_of([:html, {:local, "button"}, {:remote, "Layouts.app"}]),
          attrs <- list_of(member_of(~w(class style)), max_length: 2)
        ) do
      {kind, Enum.uniq(attrs)}
    end
  end

  defp template(tags) do
    Enum.map_join(tags, "\n", fn {kind, attrs} ->
      attrs = Enum.map_join(attrs, "", &~s( #{&1}="x"))

      case kind do
        :html -> ~s(<div#{attrs}></div>)
        {:local, name} -> ~s(<.#{name}#{attrs}></.#{name}>)
        {:remote, name} -> ~s(<#{name}#{attrs}></#{name}>)
      end
    end)
  end
end
