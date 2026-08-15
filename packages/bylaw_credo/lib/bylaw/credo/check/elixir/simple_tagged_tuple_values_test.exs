defmodule Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValuesTest do
  use Credo.Test.Case
  use ExUnitProperties

  test "allows a variable as an ok tuple value" do
    """
    defmodule Example do
      def result(value), do: {:ok, value}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> refute_issues()
  end

  test "allows scalar literals as tagged tuple values" do
    """
    defmodule Example do
      def atom, do: {:ok, :ready}
      def boolean, do: {:ok, true}
      def nil_value, do: {:ok, nil}
      def integer, do: {:ok, 42}
      def float, do: {:ok, 3.14}
      def string, do: {:ok, "ready"}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> refute_issues()
  end

  @doc """
  Issue: Negative integers and floats are scalar literals, but the check treats
  their unary-minus AST representation as a complex operator expression.

  Why it matters: Valid tagged tuples containing negative numeric results are
  incorrectly reported and force callers to introduce unnecessary variables.
  """
  test "allows negative numeric literals as tagged tuple values" do
    """
    defmodule Example do
      def integer, do: {:ok, -42}
      def float, do: {:ok, -3.14}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> refute_issues()
  end

  test "allows variables in every value position of a reply tuple" do
    """
    defmodule Example do
      def result(reply, state), do: {:reply, reply, state}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> refute_issues()
  end

  test "allows a tagged tuple containing another tagged tuple whose leaf value is a variable" do
    """
    defmodule Example do
      def result(value), do: {:cont, {:ok, value}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> refute_issues()
  end

  test "allows recursively nested tagged tuples whose leaf values are scalar literals" do
    """
    defmodule Example do
      def result, do: {:cont, {:reply, :accepted, {:ok, 42}}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> refute_issues()
  end

  test "reports a map constructed inside an ok tuple" do
    """
    defmodule Example do
      def result, do: {:ok, %{status: :ready}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports the comparison summary map constructed inside an ok tuple" do
    """
    defmodule Example do
      def compare(expected_count, actual_count) do
        {:ok,
         %{
           expected_count: expected_count,
           actual_count: actual_count,
           matching?: expected_count == actual_count
         }}
      end
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a map constructed inside an ok tuple nested beneath a cont tuple" do
    """
    defmodule Example do
      def result, do: {:cont, {:ok, %{status: :ready}}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports the commit accumulator map inside an ok tuple nested beneath a cont tuple" do
    """
    defmodule Example do
      def commit(acc, entry) do
        {:cont, {:ok, %{acc | committed: [entry | acc.committed]}}}
      end
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a function call several tagged tuple levels beneath the outer return tuple" do
    """
    defmodule Example do
      def result(value), do: {:cont, {:reply, :accepted, {:ok, normalize(value)}}}

      defp normalize(value), do: value
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a struct constructed inside an ok tuple" do
    """
    defmodule Example do
      def result, do: {:ok, %URI{scheme: "https", host: "example.com"}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a list constructed inside an ok tuple" do
    """
    defmodule Example do
      def result(first, second), do: {:ok, [first, second]}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports an empty list inside an ok tuple with its source location" do
    """
    defmodule Example do
      def result do
        {:ok, []}
      end
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issue(%{line_no: 3, column: 5, trigger: "{:ok, []}"})
  end

  test "reports an untagged tuple nested inside a tagged tuple" do
    """
    defmodule Example do
      def result(left, right), do: {:ok, {left, right}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports field access inside an ok tuple" do
    """
    defmodule Example do
      def result(user), do: {:ok, user.email}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a function call inside an ok tuple" do
    """
    defmodule Example do
      def result(value), do: {:ok, normalize(value)}

      defp normalize(value), do: value
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a pipeline inside an ok tuple" do
    """
    defmodule Example do
      def result(value), do: {:ok, value |> String.trim() |> String.downcase()}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports string interpolation inside an ok tuple" do
    """
    defmodule Example do
      def result(name), do: {:ok, "Hello, \#{name}"}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports an operator expression inside an ok tuple" do
    """
    defmodule Example do
      def result(count), do: {:ok, count + 1}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(1)
  end

  test "reports a complex value in any position of a reply tuple" do
    """
    defmodule Example do
      def complex_reply(reply, state), do: {:reply, %{body: reply}, state}
      def complex_state(reply, state), do: {:reply, reply, %{state: state}}
    end
    """
    |> to_source_file()
    |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
    |> assert_issues(2)
  end

  property "allows recursively nested tagged tuples when every generated leaf is a scalar literal or variable" do
    check all(
            depth <- integer(0..5),
            leaf <- member_of(["value", ":ready", "true", "nil", "42", "3.14", ~s("ready")])
          ) do
      expression =
        :tag
        |> List.duplicate(depth)
        |> Enum.reduce(leaf, fn :tag, nested ->
          "{:ok, #{nested}}"
        end)

      """
      defmodule Example do
        def result(value), do: {:cont, #{expression}}
      end
      """
      |> to_source_file()
      |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
      |> refute_issues()
    end
  end

  property "reports recursively nested tagged tuples when any generated leaf is a complex expression" do
    check all(
            depth <- integer(0..5),
            complex_leaf <-
              member_of([
                "%{status: value}",
                "%URI{path: value}",
                "[value]",
                "{value, :ready}",
                "value.name",
                "normalize(value)",
                ~S("value: #{value}"),
                "value + 1"
              ]),
            position <- member_of([:reply, :state])
          ) do
      reply =
        case position do
          :reply -> "{:reply, #{complex_leaf}, value}"
          :state -> "{:reply, value, #{complex_leaf}}"
        end

      expression =
        :tag
        |> List.duplicate(depth)
        |> Enum.reduce(reply, fn :tag, nested ->
          "{:ok, #{nested}}"
        end)

      """
      defmodule Example do
        def result(value), do: {:cont, #{expression}}
        defp normalize(value), do: value
      end
      """
      |> to_source_file()
      |> run_check(Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues)
      |> assert_issues(1)
    end
  end
end
