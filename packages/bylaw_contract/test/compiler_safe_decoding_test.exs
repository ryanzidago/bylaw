defmodule Bylaw.Contract.CompilerSafeDecodingTest do
  use ExUnit.Case, async: true, group: :contract_qa_fixture

  test "checker-only struct field atoms remain unsupported until the defining module is loaded" do
    assert_fixture("ColdChecker", "cold_checker", "cold_checker_field", false)
  end

  test "renamed modules and applications preserve cold and preloaded checker decoding behavior" do
    assert_fixture("RenamedChecker", "renamed_checker", "renamed_checker_field", false)
    assert_fixture("PreloadedChecker", "preloaded_checker", "preloaded_checker_field", true)
  end

  defp assert_fixture(namespace, application, field, preload?) do
    directory =
      Path.join(System.tmp_dir!(), "bylaw-checker-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule #{namespace}.Structure do
      defstruct [:#{field}]
    end

    defmodule #{namespace}.Target do
      def identity(%#{namespace}.Structure{} = value), do: value
    end
    """)

    {output, status} =
      System.cmd("elixirc", ["-o", directory, source], stderr_to_stdout: true)

    assert status == 0, output

    File.write!(Path.join(directory, "#{application}.app"), """
    {application, #{application}, [{vsn, "1"},
      {modules, ['Elixir.#{namespace}.Structure', 'Elixir.#{namespace}.Target']}]}.
    """)

    script = Path.join(directory, "inspect.exs")

    File.write!(script, """
    :ok = Application.load(:#{application})
    Code.ensure_loaded!(Bylaw.Contract.CompilerInference)
    Code.ensure_loaded!(Bylaw.Contract.CompilerInference.Elixir120)
    Code.ensure_loaded!(Bylaw.Contract.CompilerTypeMatcher)
    Code.ensure_loaded!(Module.Types.Descr)
    target = #{namespace}.Target
    structure = #{namespace}.Structure
    field = #{inspect(field)}
    exists? = fn ->
      try do
        String.to_existing_atom(field)
        true
      rescue
        ArgumentError -> false
      end
    end
    false = exists?.()
    if #{preload?}, do: Code.ensure_loaded!(structure)
    Code.ensure_loaded!(target)
    {^target, binary, _} = :code.get_object_code(target)
    {:ok, {^target, chunks}} = :beam_lib.chunks(binary, [~c"ExCk", :debug_info])
    {_, chunk} = List.keyfind(chunks, ~c"ExCk", 0)
    #{preload?} = exists?.()
    safe? = fn ->
      try do
        :erlang.binary_to_term(chunk, [:safe])
        true
      rescue
        ArgumentError -> false
      end
    end
    #{preload?} = safe?.()
    assert_decoded_status = fn loaded ->
      {version, _} = :erlang.binary_to_term(chunk, [:safe])
      case version do
        :elixir_checker_v8 ->
          [%{status: :supported}] = loaded.modules
        :elixir_checker_v3 ->
          [%{status: :unsupported, reason: reason}] = loaded.modules
          "unsupported Elixir checker version :elixir_checker_v3" = reason
          [] = loaded.return_alternatives
      end
    end
    load = fn load, attempts ->
      result = Bylaw.Contract.CompilerInference.load([target])
      case result.modules do
        [%{reason: "compiler inference inspection exceeded 100ms"}] when attempts > 1 ->
          load.(load, attempts - 1)
        _ ->
          result
      end
    end
    initial = load.(load, 3)
    if #{preload?} do
      assert_decoded_status.(initial)
    else
      [%{status: :unsupported, reason: reason}] = initial.modules
      "Elixir checker chunk was rejected by safe term decoding" = reason
      [] = initial.return_alternatives
      [] = initial.inference_rules
      [_] = initial.warnings
      false = exists?.()
    end
    Code.ensure_loaded!(structure)
    true = exists?.()
    true = safe?.()
    assert_decoded_status.(load.(load, 3))
    IO.puts("verified cold/preloaded checker state")
    """)

    ebin = Bylaw.Contract.CompilerInference |> :code.which() |> Path.dirname()

    {output, status} =
      System.cmd("elixir", ["-pa", ebin, "-pa", directory, script], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "verified cold/preloaded checker state"
  end
end
