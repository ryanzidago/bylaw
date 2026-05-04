defmodule Bylaw.Credo.Check.NoThenTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.NoThen

  test "reports direct, qualified, and piped then usage" do
    """
    defmodule Example do
      def wrap(value) do
        one = then(value, &{:ok, &1})
        two = Kernel.then(value, &{:ok, &1})
        three = value |> then(&{:ok, &1})
        four = value |> Kernel.then(&{:ok, &1})
        {one, two, three, four}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoThen)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 3, trigger: "then", message: ~r/explicit control flow/},
      %{line_no: 4, trigger: "Kernel.then", message: ~r/explicit control flow/},
      %{line_no: 5, trigger: "then", message: ~r/explicit control flow/},
      %{line_no: 6, trigger: "Kernel.then", message: ~r/explicit control flow/}
    ])
  end

  test "does not report other then-like calls" do
    """
    defmodule Example do
      def wrap(value) do
        Example.Helpers.then(value)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoThen)
    |> refute_issues()
  end
end
