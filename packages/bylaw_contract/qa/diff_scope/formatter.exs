Code.require_file("source.exs", __DIR__)
Code.require_file("runtime.exs", __DIR__)

defmodule BylawDiffScope.Formatter do
  use GenServer

  @impl GenServer
  def init(options) do
    Code.prepend_path(System.fetch_env!("BYLAW_DIFF_EBIN"))
    mode = System.fetch_env!("BYLAW_DIFF_MODE")

    {prototype_us, :ok} =
      if mode == "diff" do
        :timer.tc(fn -> BylawDiffScope.Runtime.install!(Path.expand("../..", __DIR__)) end)
      else
        {0, :ok}
      end

    {selection_us, selection_result} = :timer.tc(fn -> selection(mode) end)

    case selection_result do
      {:ok, selection} ->
        checks =
          if mode == "diff",
            do: BylawDiffScope.Runtime.checks(selection.selected),
            else: [
              Bylaw.Contract.Check.Typespec,
              Bylaw.Contract.Check.FunctionClauses,
              Bylaw.Contract.Check.ElixirCompiler
            ]

        initial_memory = :erlang.memory(:total)

        {init_us, {:ok, delegate}} =
          :timer.tc(fn ->
            if mode == "disabled",
              do: {:ok, %{tracer: nil}},
              else:
                Bylaw.Contract.ExUnitFormatter.init(
                  Keyword.put(options, :bylaw_contract, checks: checks)
                )
          end)

        if Map.get(delegate, :error), do: raise("formatter init: #{inspect(delegate.error)}")

        {:ok,
         %{
           delegate: delegate,
           mode: mode,
           selection: selection,
           selection_us: selection_us,
           prototype_us: prototype_us,
           init_us: init_us,
           initial_memory: initial_memory,
           initialized_memory: :erlang.memory(:total),
           tests: 0,
           failed: 0,
           excluded: 0,
           started: nil,
           init_count: if(mode == "disabled", do: 0, else: 1)
         }}

      {:error, reasons} ->
        File.write!(
          System.fetch_env!("BYLAW_DIFF_OUTPUT"),
          :erlang.term_to_binary(%{error: reasons, selection_us: selection_us})
        )

        raise "diff selection unresolved: #{inspect(reasons)}"
    end
  end

  defp selection("diff"),
    do:
      BylawDiffScope.Source.git_select(File.cwd!(), System.fetch_env!("BYLAW_CONTRACT_DIFF_BASE"))

  defp selection(_), do: {:ok, %{selected: :all}}

  @impl GenServer
  def handle_cast({:suite_started, _} = event, state) do
    {:noreply, forward(event, %{state | started: System.monotonic_time(:microsecond)})}
  end

  def handle_cast({:test_finished, test} = event, state) do
    state = %{
      state
      | tests: state.tests + 1,
        failed: state.failed + if(match?({:failed, _}, test.state), do: 1, else: 0),
        excluded: state.excluded + if(match?({:excluded, _}, test.state), do: 1, else: 0)
    }

    {:noreply, forward(event, state)}
  end

  def handle_cast({:suite_finished, _}, state) do
    suite_us = System.monotonic_time(:microsecond) - state.started

    {stop_us, coverage} =
      :timer.tc(fn ->
        if state.delegate.tracer, do: Bylaw.Contract.stop(state.delegate.tracer), else: nil
      end)

    {report_us, report} =
      :timer.tc(fn ->
        if coverage do
          {:ok, io} = StringIO.open("")
          Bylaw.Contract.print_report(coverage, io, colors: false)
          {_, result} = StringIO.contents(io)
          StringIO.close(io)
          result
        else
          ""
        end
      end)

    if state.mode == "diff" && coverage do
      for field <- [
            :input_classes,
            :boundaries,
            :return_alternatives,
            :compiler_return_alternatives,
            :clauses,
            :arities
          ],
          target <- Map.fetch!(coverage, field) do
        unless MapSet.member?(
                 state.selection.selected,
                 {target.module, target.function, target.arity}
               ),
               do: raise("out-of-scope target #{inspect(target)}")
      end
    end

    result =
      state
      |> Map.drop([:delegate, :started])
      |> Map.merge(%{
        suite_us: suite_us,
        stop_us: stop_us,
        report_us: report_us,
        final_memory: :erlang.memory(:total),
        report_bytes: byte_size(report),
        complete: !coverage || Map.get(coverage, :status) != :incomplete,
        coverage: coverage,
        stopped: !state.delegate.tracer || !Process.alive?(state.delegate.tracer),
        runtime: %{
          elixir: System.version(),
          otp: System.otp_release(),
          schedulers: System.schedulers_online()
        }
      })

    File.write!(System.fetch_env!("BYLAW_DIFF_OUTPUT"), :erlang.term_to_binary(result))

    IO.puts(
      "Bylaw diff prototype: #{state.mode} tests=#{state.tests} failed=#{state.failed} complete=#{result.complete} selected=#{if(state.selection.selected == :all, do: "all", else: MapSet.size(state.selection.selected))}"
    )

    {:noreply, put_in(state.delegate.tracer, nil)}
  end

  def handle_cast(event, state), do: {:noreply, forward(event, state)}

  defp forward(_event, %{mode: "disabled"} = state), do: state

  defp forward(event, state) do
    {:noreply, delegate} = Bylaw.Contract.ExUnitFormatter.handle_cast(event, state.delegate)
    %{state | delegate: delegate}
  end

  @impl GenServer
  def terminate(reason, state) do
    if state.mode != "disabled",
      do: Bylaw.Contract.ExUnitFormatter.terminate(reason, state.delegate)

    :ok
  end
end
