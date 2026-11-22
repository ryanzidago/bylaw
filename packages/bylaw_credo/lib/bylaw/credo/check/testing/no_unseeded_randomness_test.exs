defmodule Bylaw.Credo.Check.Testing.NoUnseededRandomnessTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.NoUnseededRandomness

  test "reports :rand and Enum random functions with their line" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "builds data" do
        a = :rand.uniform(100)
        b = :rand.uniform()
        c = :rand.uniform_real()
        d = :rand.normal()
        e = :rand.bytes(4)
        f = Enum.random([1, 2, 3])
        g = Enum.shuffle([1, 2, 3])
        h = Enum.take_random([1, 2, 3], 2)
        assert [a, b, c, d, e, f, g, h]
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {5, ":rand.uniform"},
               {6, ":rand.uniform"},
               {7, ":rand.uniform_real"},
               {8, ":rand.normal"},
               {9, ":rand.bytes"},
               {10, "Enum.random"},
               {11, "Enum.shuffle"},
               {12, "Enum.take_random"}
             ]
    end)
  end

  test "reports randomness piped into and passed to other calls" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "builds data" do
        users = [1, 2, 3] |> Enum.shuffle() |> Enum.map(&user_fixture(id: &1))
        assert Enum.sum(users) == Enum.random(1..10)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [5, 6] end)
  end

  test "gives the fix in the message" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "builds data" do
        assert Enum.random([1])
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Control time and chance: avoid `Enum.random` in tests - the data differs on every run and a failure cannot be repeated. " <>
                 "Use a fixed value, or draw it from a StreamData generator in a property test so ExUnit's seed brings it back."
    end)
  end

  test "reports randomness in test support files" do
    """
    defmodule MyApp.Fixtures do
      def price, do: :rand.uniform(100)
    end
    """
    |> to_source_file("test/support/fixtures.ex")
    |> run_check(NoUnseededRandomness)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "allows randomness inside property, check all and gen all blocks" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      use ExUnitProperties

      property "sums" do
        xs = Enum.shuffle([1, 2, 3])
        assert Enum.sum(xs) == 6
      end

      test "checks" do
        check all xs <- list_of(integer()) do
          assert Enum.shuffle(xs) |> Enum.sort() == Enum.sort(xs)
        end
      end

      def generator do
        gen all x <- integer() do
          {x, Enum.random([1, 2])}
        end
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> refute_issues()
  end

  test "allows randomness inside an argument of a StreamData function" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      alias StreamData, as: SD

      def generator do
        SD.map(SD.integer(), fn n -> n + :rand.uniform(3) end)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> refute_issues()
  end

  test "still reports randomness in a plain test next to a property" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      use ExUnitProperties

      property "fine" do
        assert Enum.random([1]) == 1
      end

      test "not fine" do
        assert Enum.random([1]) == 1
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> assert_issue(fn issue -> assert issue.line_no == 10 end)
  end

  test "allows the explicit-state and seeding functions of :rand" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "draws repeatably" do
        state = :rand.seed_s(:exsss, ExUnit.configuration()[:seed])
        {n, _state} = :rand.uniform_s(100, state)
        :rand.seed(:exsss, {1, 2, 3})
        {m, _state} = :rand.normal_s(state)
        assert n + m
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> refute_issues()
  end

  test "allows System.unique_integer by default" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "names things" do
        email = "user\#{System.unique_integer([:positive])}@example.com"
        table = :"table_\#{:erlang.unique_integer([:positive])}"
        assert {email, table, make_ref()}
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> refute_issues()
  end

  test "reports System.unique_integer when listed in :functions" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "builds data" do
        assert System.unique_integer([:positive]) > 0
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness, functions: [{System, [:unique_integer]}])
    |> assert_issue(fn issue -> assert issue.trigger == "System.unique_integer" end)
  end

  test "resolves aliases" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      alias Enum, as: E

      test "builds data" do
        assert E.random([1, 2])
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoUnseededRandomness)
    |> assert_issue(fn issue -> assert issue.trigger == "Enum.random" end)
  end

  test "ignores library code" do
    """
    defmodule MyApp.Picker do
      def pick(list), do: Enum.random(list)
    end
    """
    |> to_source_file("lib/my_app/picker.ex")
    |> run_check(NoUnseededRandomness)
    |> refute_issues()
  end

  test "skips files matching :excluded_paths" do
    """
    defmodule MyApp.Chaos do
      def pick(list), do: Enum.random(list)
    end
    """
    |> to_source_file("test/support/chaos.ex")
    |> run_check(NoUnseededRandomness, excluded_paths: ["test/support/chaos.ex"])
    |> refute_issues()
  end
end
