defmodule Bylaw.Contract.ObservationAcceptanceTest do
  use ExUnit.Case

  import Bylaw.Contract.ContractHelper

  alias Bylaw.Contract
  alias Bylaw.Contract.Fixtures.Countdown
  alias Bylaw.Contract.Fixtures.Greeter
  alias Bylaw.Contract.Fixtures.Raiser

  test "restores every observed module to its original binary and file when the session stops" do
    original = {Greeter.module_info(:md5), :code.which(Greeter)}

    {:ok, session} = Contract.start([Greeter])

    try do
      refute Greeter.module_info(:md5) == elem(original, 0)
    after
      Contract.stop(session)
    end

    assert {Greeter.module_info(:md5), :code.which(Greeter)} == original
  end

  test "keeps the module's compile source path while it is instrumented" do
    source = Greeter.module_info(:compile)[:source]

    {:ok, session} = Contract.start([Greeter])

    try do
      assert Greeter.module_info(:compile)[:source] == source
      assert Greeter.__info__(:compile)[:source] == source
    after
      Contract.stop(session)
    end
  end

  test "counts exactly when many processes call observed functions concurrently" do
    processes = 8
    per_process = 100_000

    report =
      Contract.observe([Greeter], fn ->
        1..processes
        |> Task.async_stream(
          fn _process -> for _call <- 1..per_process, do: Greeter.greet(:admin) end,
          max_concurrency: processes,
          timeout: :infinity
        )
        |> Stream.run()
      end)

    assert property(report, Greeter, :clause, {:greet, 1, 1}).count == processes * per_process
  end

  test "refuses to start a second session while one is active" do
    {:ok, session} = Contract.start([Greeter])

    try do
      assert {:error, :session_active} = Contract.start([Greeter])
    after
      Contract.stop(session)
    end

    assert {:ok, again} = Contract.start([Greeter])
    Contract.stop(again)
  end

  test "counts the selected clause even when the function raises throws or exits" do
    report =
      Contract.observe([Raiser], fn ->
        assert Raiser.run(:ok) == :ok
        assert_raise ArgumentError, fn -> Raiser.run(:raise) end
        assert catch_throw(Raiser.run(:throw)) == :fixture_throw
        assert catch_exit(Raiser.run(:exit)) == :fixture_exit
      end)

    assert missed(report, Raiser, :clause) == []
  end

  test "still raises FunctionClauseError naming the original function when no clause matches" do
    Contract.observe([Greeter], fn ->
      assert_raise FunctionClauseError, ~r/Bylaw.Contract.Fixtures.Greeter.greet\/1/, fn ->
        apply(Greeter, :greet, [:unknown])
      end
    end)
  end

  test "keeps tail calls so deep recursion does not grow the stack" do
    assert {:killed, _reason} = bounded_heap(fn -> non_tail_count(1_000_000) end)

    Contract.observe([Countdown], fn ->
      assert {:ok, :done} = bounded_heap(fn -> Countdown.count_down(1_000_000) end)
    end)
  end

  test "reports a module without a BEAM file as a warning instead of crashing" do
    [{module, _binary}] =
      Code.compile_string("""
      defmodule Bylaw.Contract.Fixtures.InMemory do
        @spec pick(:a | :b) :: :a | :b
        def pick(:a), do: :a
        def pick(:b), do: :b
      end
      """)

    report = Contract.observe([module], fn -> module.pick(:a) end)

    assert report.properties == []
    assert Enum.any?(report.warnings, &(&1 =~ "InMemory"))
  end

  defp non_tail_count(0), do: 0
  defp non_tail_count(count), do: 1 + non_tail_count(count - 1)

  defp bounded_heap(fun) do
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn -> send(parent, {ref, fun.()}) end,
        [:monitor, max_heap_size: %{size: 1_000_000, kill: true, error_logger: false}]
      )

    receive do
      {^ref, result} -> {:ok, result}
      {:DOWN, ^monitor, :process, ^pid, reason} -> {:killed, reason}
    after
      60_000 -> flunk("call did not finish")
    end
  end
end
