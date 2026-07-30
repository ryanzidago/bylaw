defmodule Bylaw.Credo.Check.Elixir.PreferBlockIfTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.PreferBlockIf

  test "reports inline if expressions with do and else keywords" do
    """
    defmodule Example do
      def validate(value), do: if(value, do: :ok, else: :error)
    end
    """
    |> to_source_file()
    |> run_check(PreferBlockIf)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.trigger == "if"
      assert issue.message =~ "block syntax"
    end)
  end

  test "reports wrapped keyword-form if expressions" do
    """
    defmodule Example do
      def validate(value) do
        if value,
          do: :ok,
          else: :error
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferBlockIf)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.trigger == "if"
    end)
  end

  test "allows block-form if expressions" do
    """
    defmodule Example do
      def validate(value) do
        if value do
          :ok
        else
          :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferBlockIf)
    |> refute_issues()
  end
end
