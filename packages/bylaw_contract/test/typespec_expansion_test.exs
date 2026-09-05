defmodule Bylaw.Contract.TypespecExpansionTest do
  use ExUnit.Case

  alias Bylaw.Contract.Specs
  alias Bylaw.Contract.TypeMatcher

  test "repeated alias graphs have near-linear representation size after process copying" do
    sizes =
      for depth <- [4, 8, 12] do
        with_module(repeated_types(depth), fn module ->
          [target] = Specs.load([module]).input_classes
          assert target.supported?
          Task.async(fn -> :erts_debug.flat_size(target.match_type) end) |> Task.await()
        end)
      end

    [small, medium, large] = sizes
    assert medium < small * 3
    assert large < small * 4
  end

  test "compact repeated aliases preserve matching after process copying" do
    with_module(repeated_types(8), fn module ->
      [target] = Specs.load([module]).input_classes
      valid = Enum.reduce(1..8, 7, fn _, child -> {child, child} end)
      invalid = put_elem(valid, 0, :invalid)

      assert Task.async(fn ->
               {TypeMatcher.match(valid, target.match_type),
                TypeMatcher.match(invalid, target.match_type)}
             end)
             |> Task.await() == {:match, :no_match}

      {:ok, tracer} =
        Bylaw.Contract.start([module], checks: [Bylaw.Contract.Check.Typespec])

      assert Task.async(fn -> module.f(valid) end) |> Task.await() == :ok
      coverage = Bylaw.Contract.stop(tracer)
      assert Map.fetch!(coverage.hits, target.id) == 1
      [copied_target] = coverage.input_classes
      assert TypeMatcher.match(valid, copied_target.match_type) == :match
    end)
  end

  test "parameterised aliases keep different argument bindings separate" do
    with_module(
      """
      @type pair(t) :: {t, t}
      @spec f({pair(integer()), pair(atom())}) :: :ok
      def f(_), do: :ok
      """,
      fn module ->
        [target] = Specs.load([module]).input_classes
        assert target.supported?
        assert TypeMatcher.match({{1, 2}, {:left, :right}}, target.match_type) == :match
        assert TypeMatcher.match({{:left, :right}, {1, 2}}, target.match_type) == :no_match
        assert TypeMatcher.match({{1, :wrong}, {:left, :right}}, target.match_type) == :no_match
      end
    )
  end

  test "recursive and opaque aliases stay unassessable" do
    with_module(
      """
      @type recursive() :: {recursive()}
      @opaque hidden() :: binary()
      @spec f(recursive(), hidden()) :: :ok
      def f(_, _), do: :ok
      """,
      fn module ->
        targets = Specs.load([module]).input_classes
        assert length(targets) == 2
        refute Enum.any?(targets, & &1.supported?)
      end
    )
  end

  test "alias expansion preserves input partitions and spec source locations" do
    with_module(
      """
      @type count() :: integer()
      @type values() :: [integer()]
      @spec f(count(), values()) :: :ok
      def f(_, _), do: :ok
      """,
      fn module ->
        targets = Specs.load([module]).input_classes

        assert Enum.map(targets, & &1.label) == [
                 "negative",
                 "zero",
                 "positive",
                 "empty",
                 "singleton",
                 "multiple"
               ]

        assert Enum.all?(targets, & &1.supported?)
        assert Enum.all?(targets, &(&1.spec_line == 4))
        assert Enum.all?(targets, &String.ends_with?(&1.spec_file, "fixture.ex"))
        assert Enum.all?(targets, &(&1.spec_source =~ "@spec f(count(), values())"))
      end
    )
  end

  test "unsupported members do not retain repeated alias graphs" do
    source =
      repeated_types(12)
      |> String.replace(
        "@spec f(t12())",
        "@opaque hidden() :: binary()\n@spec f({hidden(), t12()})"
      )

    with_module(source, fn module ->
      [target] = Specs.load([module]).input_classes
      refute target.supported?
      assert :erts_debug.flat_size(target.match_type) < 100
    end)
  end

  test "unsupported list elements preserve all length partitions" do
    with_module(
      """
      @opaque hidden() :: binary()
      @type values() :: [hidden()]
      @spec f(values()) :: :ok
      def f(_), do: :ok
      """,
      fn module ->
        targets = Specs.load([module]).input_classes
        assert Enum.map(targets, & &1.label) == ["empty", "singleton", "multiple"]
        refute Enum.any?(targets, & &1.supported?)
      end
    )
  end

  test "repeated top-level union aliases are bounded before target materialisation" do
    source = String.replace(repeated_types(14), ~r/\{(t\d+\(\)), (t\d+\(\))\}/, "\\1 | \\2")

    with_module(source, fn module ->
      parent = self()

      {pid, monitor} =
        :erlang.spawn_opt(
          fn ->
            send(parent, {:loaded, self(), Specs.load([module])})
          end,
          [:monitor, {:max_heap_size, %{size: 1_000_000, kill: true, error_logger: false}}]
        )

      try do
        receive do
          {:loaded, ^pid, loaded} ->
            [target] = loaded.input_classes
            refute target.supported?
            assert target.match_type == {:unsupported, {:union_expansion_limit, 4096}}

          {:DOWN, ^monitor, :process, ^pid, reason} ->
            flunk("union expansion did not remain bounded: #{inspect(reason)}")
        after
          10_000 -> flunk("union expansion did not finish")
        end
      after
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
      end
    end)
  end

  test "aliases in map keys and list values preserve matching" do
    with_module(
      """
      @type key() :: :id
      @type pair(t) :: {t, t}
      @spec f(%{required(key()) => [pair(integer())]}) :: :ok
      def f(_), do: :ok
      """,
      fn module ->
        [target] = Specs.load([module]).input_classes
        assert target.supported?
        assert TypeMatcher.match(%{id: [{1, 2}]}, target.match_type) == :match
        assert TypeMatcher.match(%{}, target.match_type) == :no_match
        assert TypeMatcher.match(%{id: [{1, :wrong}]}, target.match_type) == :no_match
      end
    )
  end

  defp repeated_types(depth) do
    definitions =
      Enum.map_join(1..depth, "\n", fn index ->
        "@type t#{index}() :: {t#{index - 1}(), t#{index - 1}()}"
      end)

    "@type t0() :: integer()\n#{definitions}\n@spec f(t#{depth}()) :: :ok\ndef f(_), do: :ok"
  end

  defp with_module(source, assertion) do
    module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")
    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)
    file = Path.join(directory, "fixture.ex")
    File.write!(file, "defmodule #{inspect(module)} do\n#{source}\nend\n")
    previous = Code.compiler_options()

    [{^module, binary}] =
      try do
        Code.compiler_options(debug_info: true)
        Code.compile_file(file)
      after
        Code.compiler_options(previous)
      end

    File.write!(Path.join(directory, "#{module}.beam"), binary)
    :code.delete(module)
    :code.purge(module)
    true = :code.add_patha(String.to_charlist(directory))
    {:module, ^module} = :code.load_abs(String.to_charlist(Path.join(directory, "#{module}")))

    try do
      assertion.(module)
    after
      :code.delete(module)
      :code.purge(module)
      :code.del_path(String.to_charlist(directory))
      File.rm_rf!(directory)
    end
  end
end
