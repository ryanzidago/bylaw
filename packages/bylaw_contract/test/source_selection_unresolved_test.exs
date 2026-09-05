defmodule Bylaw.Contract.SourceSelectionUnresolvedTest do
  use ExUnit.Case, async: false

  alias Bylaw.Contract.SourceSelection

  test "conditional definitions remain unresolved even when source is unchanged" do
    source = files("if System.get_env(\"BYLAW_SOURCE_CONDITION\"), do: def(run(), do: :enabled)")
    assert {:error, reasons} = select(source, source)
    assert Enum.any?(reasons, &(&1.code == :unsupported_definition_context))
  end

  test "generated functions and macro effects never return an assessed empty scope" do
    for body <- [
          "for name <- [:one, :two], do: def(unquote(name)(), do: :ok)",
          "use UnknownSourceMacro; def run(), do: :ok",
          "require UnknownSourceMacro; UnknownSourceMacro.define_functions()"
        ] do
      source = files(body)
      assert {:error, reasons} = select(source, source)
      refute Enum.empty?(reasons)
    end
  end

  test "changed shared local and remote types report unresolved impact" do
    for spec <- ["local()", "SourceTypes.t()"] do
      before = files("@type local() :: integer(); @spec run(#{spec}) :: :ok; def run(_), do: :ok")

      current =
        Map.new(before, fn {path, source} ->
          {path, String.replace(source, "integer()", "atom()")}
        end)

      assert {:error, reasons} = select(before, current)
      assert Enum.any?(reasons, &(&1.code == :unsupported_module_context))
    end

    consumer = files("@spec run(SourceTypes.t()) :: :ok; def run(_), do: :ok")

    before =
      Map.put(consumer, "lib/types.ex", "defmodule SourceTypes do; @type t() :: integer(); end")

    current =
      Map.put(consumer, "lib/types.ex", "defmodule SourceTypes do; @type t() :: atom(); end")

    assert {:error, reasons} = select(before, current)

    assert Enum.any?(
             reasons,
             &(&1.code == :unsupported_module_context and &1.module == SourceTypes)
           )
  end

  test "location sensitive source moves report unresolved reasons" do
    for expression <- ["__DIR__", "__ENV__.line", "__ENV__.file", "__CALLER__"] do
      before = files("def run(), do: #{expression}")
      [{_, source}] = Map.to_list(before)
      assert {:error, reasons} = select(before, %{"lib/moved/demo.ex" => source})
      assert Enum.any?(reasons, &(&1.code == :location_sensitive_source))
    end
  end

  test "duplicate and dynamic module definitions return structured reasons" do
    duplicates =
      Map.put(
        files("def one(), do: 1"),
        "lib/duplicate.ex",
        "defmodule SourceDemo do; def two(), do: 2; end"
      )

    assert {:error, reasons} = select(%{}, duplicates)
    assert Enum.any?(reasons, &(&1.code == :duplicate_module))

    assert {:error, reasons} =
             select(%{}, %{
               "lib/dynamic.ex" => "defmodule module_name() do; def run(), do: :ok; end"
             })

    assert Enum.any?(reasons, &(&1.code == :dynamic_module))
  end

  test "parsing never executes source expressions" do
    source = files("send(self(), :source_was_executed); def run(), do: :ok")
    assert {:error, _} = select(source, source)
    refute_received :source_was_executed
  end

  test "malformed source returns a path specific parsing reason" do
    assert {:error, reasons} = select(%{}, %{"lib/broken.ex" => "defmodule Broken do"})
    assert Enum.any?(reasons, &(&1.code == :parse_error and &1.path == "lib/broken.ex"))
  end

  test "unsupported mapping prevents partial success for otherwise selectable functions" do
    current =
      Map.put(
        files("def added(), do: :ok"),
        "lib/generated.ex",
        "defmodule GeneratedSource do; use UnknownSourceMacro; end"
      )

    assert {:error, reasons} = select(%{}, current)
    refute Enum.empty?(reasons)
  end

  test "dynamic alias segments and unquoted function names return reasons instead of crashing" do
    for body <- [
          "defmodule __MODULE__.Child do; def run(), do: :ok; end",
          "def unquote(:run), do: :ok",
          "def unquote(:run)(), do: :ok"
        ] do
      assert {:error, reasons} = select(%{}, files(body))
      assert Enum.any?(reasons, &(&1.code in [:dynamic_module, :dynamic_function]))
    end
  end

  test "top level executable source cannot become an assessed empty scope" do
    source = %{"lib/side_effect.ex" => "send(self(), :source_was_executed)"}
    assert {:error, reasons} = select(source, source)
    assert Enum.any?(reasons, &(&1.code == :unsupported_outer_context))
    refute_received :source_was_executed
  end

  test "quoted code and compile time unquote cannot hide location or generated effects" do
    for body <- [
          "def ast(), do: quote(do: other())",
          "@type t() :: unquote(type_ast()); def run(), do: :ok",
          "@spec run() :: unquote(type_ast()); def run(), do: :ok"
        ] do
      source = files(body)
      assert {:error, reasons} = select(source, source)
      assert Enum.any?(reasons, &(&1.code == :unsupported_quoted_source))
    end
  end

  test "executable documentation attributes and compile callbacks remain unresolved" do
    for body <- [
          "@doc (send(self(), :source_was_executed); \"doc\"); def run(), do: :ok",
          "@moduledoc documentation(); def run(), do: :ok",
          "@after_verify {Verifier, :verify}; def run(), do: :ok"
        ] do
      source = files(body)
      assert {:error, reasons} = select(source, source)
      assert Enum.any?(reasons, &(&1.code == :unsupported_definition_context))
      refute_received :source_was_executed
    end
  end

  defp files(body), do: %{"lib/demo.ex" => "defmodule SourceDemo do\n#{body}\nend"}
  defp select(before, current), do: apply(SourceSelection, :select, [before, current])
end
