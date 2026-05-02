defmodule Bylaw.Credo.Check.Refactor.NoNestedCaseTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Refactor.NoNestedCase

  test "reports nested case statements" do
    """
    defmodule Example do
      def run(a, b) do
        case a do
          {:ok, value} ->
            case b do
              {:ok, other} -> {:ok, value + other}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> assert_issue()
  end

  test "reports nested case after other expressions in a block" do
    """
    defmodule Example do
      def run(a, b) do
        case a do
          {:ok, value} ->
            _ignored = value
            case b do
              {:ok, other} -> {:ok, other}
              _ -> :error
            end

          _ ->
            :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> assert_issue()
  end

  test "does not report a single case" do
    """
    defmodule Example do
      def run(a) do
        case a do
          {:ok, value} -> value
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> refute_issues()
  end

  test "does not report sibling case statements" do
    """
    defmodule Example do
      def run(a, b) do
        x =
          case a do
            {:ok, value} -> value
            _ -> nil
          end

        case b do
          {:ok, value} -> {x, value}
          _ -> :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> refute_issues()
  end

  test "reports multiple nested cases in different branches" do
    """
    defmodule Example do
      def run(a, b, c) do
        case a do
          {:ok, _} ->
            case b do
              {:ok, _} -> :ok
              _ -> :error
            end

          {:error, _} ->
            case c do
              {:ok, _} -> :ok
              _ -> :error
            end
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> assert_issues()
  end

  test "does not report case nested inside an if within a branch" do
    """
    defmodule Example do
      def run(a, flag) do
        case a do
          {:ok, value} ->
            if flag do
              value
            else
              nil
            end

          _ ->
            :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> refute_issues()
  end

  test "does not report case assigned to a variable mid-block" do
    """
    defmodule Example do
      def run(a, b) do
        case a do
          {:ok, value} ->
            result =
              case b do
                {:ok, other} -> other
                _ -> nil
              end

            {:ok, result, value}

          _ ->
            :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> refute_issues()
  end

  test "does not report case inside a function call within a branch" do
    """
    defmodule Example do
      def run(a) do
        case a do
          {:ok, value} -> helper(value)
          _ -> :error
        end
      end

      defp helper(value) do
        case value do
          x when x > 0 -> :positive
          _ -> :non_positive
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoNestedCase)
    |> refute_issues()
  end
end
