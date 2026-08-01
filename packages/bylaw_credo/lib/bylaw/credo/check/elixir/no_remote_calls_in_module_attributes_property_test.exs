defmodule Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributesPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes

  property "literal attributes remain accepted across arbitrary nesting" do
    check all(literal <- literal()) do
      literal_source = inspect(literal, limit: :infinity, printable_limit: :infinity)
      source = "defmodule Example do\n  @value #{literal_source}\nend"

      source
      |> to_source_file()
      |> run_check(NoRemoteCallsInModuleAttributes)
      |> refute_issues()
    end
  end

  property "application calls are reported across arbitrary namespace depth" do
    check all(
            namespace <- list_of(module_segment(), min_length: 1, max_length: 5),
            function <- member_of(~w(values options settings)a),
            arity <- integer(0..3)
          ) do
      module = Enum.join(["MyApp" | namespace], ".")
      arguments = Enum.map_join(1..arity//1, ", ", fn _index -> ":value" end)
      source = "defmodule Example do\n  @value #{module}.#{function}(#{arguments})\nend"

      source
      |> to_source_file()
      |> run_check(NoRemoteCallsInModuleAttributes)
      |> assert_issue(%{trigger: "#{module}.#{function}"})
    end
  end

  defp literal do
    scalar =
      one_of([
        integer(),
        boolean(),
        string(:printable),
        member_of([nil, :ok, :error])
      ])

    tree(scalar, fn nested ->
      one_of([
        list_of(nested, max_length: 5),
        map_of(string(:printable, max_length: 8), nested, max_length: 5),
        tuple({nested, nested})
      ])
    end)
  end

  defp module_segment do
    gen all(
          first <- member_of(Enum.to_list(?A..?Z)),
          rest <- list_of(member_of(Enum.to_list(?a..?z)), max_length: 10)
        ) do
      List.to_string([first | rest])
    end
  end
end
