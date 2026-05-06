defmodule Bylaw.Credo.Check.PreferEnumCountTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.PreferEnumCount

  test "reports length calls and pipeline usage" do
    """
    defmodule Example do
      def count(items) do
        one = length(items)
        two = Kernel.length(items)
        three = items |> length()
        four = items |> Kernel.length()
        {one, two, three, four}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 3, trigger: "length", message: ~r/Enum\.count/},
      %{line_no: 4, trigger: "Kernel.length", message: ~r/Enum\.count/},
      %{line_no: 5, trigger: "length", message: ~r/Enum\.count/},
      %{line_no: 6, trigger: "Kernel.length", message: ~r/Enum\.count/}
    ])
  end

  test "does not report Enum.count or other length functions" do
    """
    defmodule Example do
      def count(items, name) do
        {Enum.count(items), String.length(name)}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> refute_issues()
  end

  test "does not report length/1 in guard clauses" do
    """
    defmodule Example do
      def check(items) when length(items) > 10, do: :big
      def check(_items), do: :small
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> refute_issues()
  end

  test "does not report Kernel.length/1 in guard clauses" do
    """
    defmodule Example do
      def check(items) when Kernel.length(items) > 10, do: :big
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> refute_issues()
  end

  test "does not report length/1 in multi-clause guard" do
    """
    defmodule Example do
      def check(items) when is_list(items) and length(items) > 0, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> refute_issues()
  end

  test "still reports length/1 in function body even when guard uses it too" do
    """
    defmodule Example do
      def check(items) when length(items) > 10 do
        length(items)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.trigger == "length"
    end)
  end

  test "does not report length/1 in defp guard clauses" do
    """
    defmodule Example do
      defp validate(items) when length(items) > 10, do: {:error, :too_many}
      defp validate(_items), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumCount)
    |> refute_issues()
  end
end
