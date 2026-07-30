defmodule Bylaw.Credo.Check.HEEx.NoDuplicateStaticIdsPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds

  property "static ids report one issue for every occurrence after the first" do
    check all(ids <- list_of(identifier(), max_length: 12)) do
      unique_id_count =
        ids
        |> Enum.uniq()
        |> Enum.count()

      expected_issue_count = Enum.count(ids) - unique_id_count

      ids
      |> template()
      |> Credo.SourceFile.parse("lib/example/index.html.heex")
      |> run_check(NoDuplicateStaticIds)
      |> assert_issues(expected_issue_count)
    end
  end

  property "unique static ids never report issues" do
    check all(ids <- uniq_list_of(identifier(), max_length: 12)) do
      ids
      |> template()
      |> Credo.SourceFile.parse("lib/example/index.html.heex")
      |> run_check(NoDuplicateStaticIds)
      |> refute_issues()
    end
  end

  property "dynamic ids never contribute duplicate issues" do
    check all(names <- list_of(identifier(), max_length: 12)) do
      source =
        Enum.map_join(names, "\n", fn name ->
          ~s(<div id={@#{String.replace(name, "-", "_")}}></div>)
        end)

      source
      |> Credo.SourceFile.parse("lib/example/index.html.heex")
      |> run_check(NoDuplicateStaticIds)
      |> refute_issues()
    end
  end

  property "duplicate detection is unchanged by element names and harmless whitespace" do
    check all(
            ids <- list_of(identifier(), max_length: 12),
            elements <-
              list_of(member_of(["div", "span", "section", "article"]), length: Enum.count(ids))
          ) do
      compact = template(ids)

      spaced =
        ids
        |> Enum.zip(elements)
        |> Enum.map_join("\n\n", fn {id, element} ->
          ~s(  <#{element}  class="generated"  id="#{id}" ></#{element}>  )
        end)

      compact_issues =
        compact
        |> Credo.SourceFile.parse("lib/example/compact.html.heex")
        |> run_check(NoDuplicateStaticIds)

      spaced_issues =
        spaced
        |> Credo.SourceFile.parse("lib/example/spaced.html.heex")
        |> run_check(NoDuplicateStaticIds)

      assert Enum.count(spaced_issues) == Enum.count(compact_issues)
    end
  end

  property "identical static ids in separate H sigils remain isolated" do
    check all(id <- identifier()) do
      """
      defmodule Example do
        def header(assigns) do
          ~H\"\"\"
          <header id="#{id}"></header>
          \"\"\"
        end

        def footer(assigns) do
          ~H\"\"\"
          <footer id="#{id}"></footer>
          \"\"\"
        end
      end
      """
      |> to_source_file("lib/example.ex")
      |> run_check(NoDuplicateStaticIds)
      |> refute_issues()
    end
  end

  defp identifier do
    rest_characters =
      Enum.concat([Enum.to_list(?a..?z), Enum.to_list(?0..?9), [?-]])

    gen all(
          first <- member_of(Enum.to_list(?a..?z)),
          rest <- list_of(member_of(rest_characters), max_length: 10)
        ) do
      List.to_string([first | rest])
    end
  end

  defp template(ids) do
    Enum.map_join(ids, "\n", fn id -> ~s(<div id="#{id}"></div>) end)
  end
end
