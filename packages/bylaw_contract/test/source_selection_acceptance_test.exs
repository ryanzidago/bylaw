defmodule Bylaw.Contract.SourceSelectionAcceptanceTest do
  use ExUnit.Case, async: false

  alias Bylaw.Contract.SourceSelection

  test "explicit source maps select changed authored functions without repository access" do
    assert {:ok, selected} = select(%{}, files("def run(value), do: value"))
    assert selected == MapSet.new([{SourceDemo, :run, 1}])
  end

  test "body head guard and spec changes select the complete current function" do
    before = "@spec run(integer()) :: integer(); def run(0), do: 0; def run(x) when x > 0, do: x"

    for current <- [
          String.replace(before, "do: x", "do: x + 1"),
          String.replace(before, "run(0)", "run(1)"),
          String.replace(before, "x > 0", "x >= 0"),
          String.replace(before, ":: integer()", ":: number()")
        ] do
      assert {:ok, selected} = select(files(before), files(current))
      assert selected == MapSet.new([{SourceDemo, :run, 1}])
    end
  end

  test "clause deletion and renames select only surviving current callable identities" do
    before = files("def run(0), do: 0; def run(x), do: x; def old(), do: :ok")
    assert {:ok, selected} = select(before, files("def run(x), do: x; def renamed(), do: :ok"))
    assert selected == MapSet.new([{SourceDemo, :run, 1}, {SourceDemo, :renamed, 0}])
    assert {:ok, empty} = select(before, %{})
    assert Enum.empty?(empty)
  end

  test "private functions and all default arities remain in the selected function scope" do
    before =
      files(
        ~S"@spec run() :: integer(); def run(a \\ 1, b \\ 2), do: hidden(a + b); defp hidden(x), do: x"
      )

    current =
      Map.new(before, fn {path, source} ->
        {path, String.replace(source, "integer()", "number()")}
      end)

    assert {:ok, selected} = select(before, current)

    assert selected ==
             MapSet.new([{SourceDemo, :run, 0}, {SourceDemo, :run, 1}, {SourceDemo, :run, 2}])

    assert {:ok, added} = select(%{}, current)
    assert MapSet.member?(added, {SourceDemo, :hidden, 1})
  end

  test "formatting and location independent file moves preserve empty selection" do
    before = files("def run(x), do: x + 1")
    current = %{"lib/moved.ex" => "defmodule SourceDemo do\n def run(x) do\n x + 1\n end\nend"}
    assert {:ok, selected} = select(before, current)
    assert Enum.empty?(selected)
  end

  test "moving definitions across attributes follows compiled behavior" do
    before =
      "defmodule SourceAttributeOracle do; @value 1; def run(), do: @value; @value 2; def last(), do: @value; end"

    current =
      "defmodule SourceAttributeOracle do; @value 1; @value 2; def run(), do: @value; def last(), do: @value; end"

    assert compile_value(before, SourceAttributeOracle, :run) == 1
    assert compile_value(current, SourceAttributeOracle, :run) == 2
    assert {:ok, selected} = select(%{"lib/oracle.ex" => before}, %{"lib/oracle.ex" => current})
    assert selected == MapSet.new([{SourceAttributeOracle, :run, 0}])
  end

  test "moving specs across aliases retains declaration context" do
    spec = "@spec run(Type.t()) :: :ok"
    before = files("alias String, as: Type; #{spec}; alias MapSet, as: Type; def run(_), do: :ok")

    current =
      files("alias String, as: Type; alias MapSet, as: Type; #{spec}; def run(_), do: :ok")

    assert {:ok, selected} = select(before, current)
    assert selected == MapSet.new([{SourceDemo, :run, 1}])
  end

  test "nested implicit aliases retain lexical declaration order" do
    first = "defmodule First do; def value(), do: :first; end"
    second = "defmodule Second do; def value(), do: First; end"
    before = "defmodule SourceAliasOracle do; #{first}; #{second}; end"
    current = "defmodule SourceAliasOracle do; #{second}; #{first}; end"
    assert compile_value(before, SourceAliasOracle.Second, :value) == SourceAliasOracle.First
    assert compile_value(current, SourceAliasOracle.Second, :value) == First
    assert {:ok, selected} = select(%{"lib/oracle.ex" => before}, %{"lib/oracle.ex" => current})
    assert MapSet.member?(selected, {SourceAliasOracle.Second, :value, 0})
  end

  test "new static module names can be selected before compilation" do
    name = "BylawFreshSource#{System.unique_integer([:positive])}"

    assert {:ok, selected} =
             select(%{}, %{"lib/new.ex" => "defmodule #{name} do; def run(), do: :ok; end"})

    [{module, :run, 0}] = MapSet.to_list(selected)
    assert Atom.to_string(module) == "Elixir." <> name
    refute Code.loaded?(module)
  end

  test "spec changes do not select unrelated arities with the same function name" do
    before =
      files("@spec run(integer()) :: integer(); def run(x), do: x; def run(x, y), do: {x, y}")

    current =
      Map.new(before, fn {path, source} ->
        {path, String.replace(source, ":: integer()", ":: number()")}
      end)

    assert {:ok, selected} = select(before, current)
    assert selected == MapSet.new([{SourceDemo, :run, 1}])
  end

  defp files(body), do: %{"lib/demo.ex" => "defmodule SourceDemo do\n#{body}\nend"}
  defp select(before, current), do: apply(SourceSelection, :select, [before, current])

  defp compile_value(source, module, function) do
    compiled = Code.compile_string(source)

    try do
      apply(module, function, [])
    after
      for {compiled_module, _} <- compiled do
        :code.purge(compiled_module)
        :code.delete(compiled_module)
        :code.purge(compiled_module)
      end
    end
  end
end
