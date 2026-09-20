defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass

  property "every component tag carrying a class attribute reports one issue" do
    check all(tags <- list_of(tag(), max_length: 12)) do
      expected_issue_count =
        Enum.count(tags, fn {kind, class?} -> kind != :html and class? end)

      tags
      |> template()
      |> Credo.SourceFile.parse("lib/example/index.html.heex")
      |> run_check(NoComponentClass)
      |> assert_issues(expected_issue_count)
    end
  end

  property "plain HTML tags never report issues" do
    check all(names <- list_of(member_of(~w(div span section article)), max_length: 12)) do
      names
      |> Enum.map_join("\n", fn name -> ~s(<#{name} class="px-4"></#{name}>) end)
      |> Credo.SourceFile.parse("lib/example/index.html.heex")
      |> run_check(NoComponentClass)
      |> refute_issues()
    end
  end

  property "excluding a component name suppresses exactly its issues" do
    check all(
            tags <- list_of(tag(), max_length: 12),
            excluded <- member_of(~w(button banner section))
          ) do
      source = template(tags)

      all_issues =
        source
        |> Credo.SourceFile.parse("lib/example/index.html.heex")
        |> run_check(NoComponentClass)

      remaining_issues =
        source
        |> Credo.SourceFile.parse("lib/example/index.html.heex")
        |> run_check(NoComponentClass, excluded_components: [excluded])

      suppressed =
        Enum.count(tags, fn {kind, class?} -> kind == {:local, excluded} and class? end)

      assert Enum.count(remaining_issues) == Enum.count(all_issues) - suppressed
    end
  end

  defp tag do
    gen all(
          kind <-
            member_of([
              :html,
              {:local, "button"},
              {:local, "banner"},
              {:local, "section"},
              {:remote, "Layouts.app"}
            ]),
          class? <- boolean()
        ) do
      {kind, class?}
    end
  end

  defp template(tags) do
    Enum.map_join(tags, "\n", fn {kind, class?} ->
      class =
        if class? do
          ~s( class="px-4")
        else
          ""
        end

      case kind do
        :html -> ~s(<div#{class}></div>)
        {:local, name} -> ~s(<.#{name}#{class}></.#{name}>)
        {:remote, name} -> ~s(<#{name}#{class}></#{name}>)
      end
    end)
  end
end
