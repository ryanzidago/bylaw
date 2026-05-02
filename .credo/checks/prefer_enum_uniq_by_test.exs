defmodule Bylaw.Credo.Check.Readability.PreferEnumUniqByTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.PreferEnumUniqBy

  test "reports direct field projections followed by Enum.uniq in a pipeline" do
    """
    defmodule Example do
      def steps(items) do
        items
        |> Enum.map(& &1.step)
        |> Enum.uniq()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> assert_issue(%{
      line_no: 5,
      trigger: "Enum.uniq",
      message: ~r/Enum\.uniq_by\(& &1\.step\) \|> Enum\.map\(& &1\.step\)/
    })
  end

  test "reports direct Enum.map calls followed by Enum.uniq" do
    """
    defmodule Example do
      def steps(items) do
        Enum.map(items, & &1.step)
        |> Enum.uniq()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> assert_issue(%{
      line_no: 4,
      trigger: "Enum.uniq",
      message: ~r/Enum\.uniq_by\(& &1\.step\) \|> Enum\.map\(& &1\.step\)/
    })
  end

  test "reports nested Enum.uniq(Enum.map(...)) calls" do
    """
    defmodule Example do
      def steps(items) do
        Enum.uniq(Enum.map(items, & &1.step))
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> assert_issue(%{
      line_no: 3,
      trigger: "Enum.uniq",
      message: ~r/Enum\.uniq_by\(& &1\.step\) \|> Enum\.map\(& &1\.step\)/
    })
  end

  test "reports anonymous functions that project a field" do
    """
    defmodule Example do
      def steps(items) do
        items
        |> Enum.map(fn item -> item.step end)
        |> Enum.uniq()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> assert_issue(%{
      line_no: 5,
      trigger: "Enum.uniq",
      message:
        ~r/Enum\.uniq_by\(fn item -> item\.step end\) \|> Enum\.map\(fn item -> item\.step end\)/
    })
  end

  test "reports nested field projections" do
    """
    defmodule Example do
      def names(items) do
        items
        |> Enum.map(& &1.profile.name)
        |> Enum.uniq()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> assert_issue()
  end

  test "does not report non-field callbacks" do
    """
    defmodule Example do
      def values(items) do
        items
        |> Enum.map(&normalize/1)
        |> Enum.uniq()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> refute_issues()
  end

  test "does not report pipelines that already use Enum.uniq_by" do
    """
    defmodule Example do
      def values(items) do
        items
        |> Enum.uniq_by(& &1.step)
        |> Enum.map(& &1.step)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> refute_issues()
  end

  test "does not report when Enum.uniq is not directly after Enum.map" do
    """
    defmodule Example do
      def values(items) do
        items
        |> Enum.map(& &1.step)
        |> Enum.sort()
        |> Enum.uniq()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEnumUniqBy)
    |> refute_issues()
  end
end
