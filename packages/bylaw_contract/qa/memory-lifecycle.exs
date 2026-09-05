# elixir -pa EBIN qa/memory-lifecycle.exs MODE SPEED MODULES FUNCTIONS DEPTH PAYLOAD PRODUCERS CALLS CYCLES OUTPUT [return_payload]
# Synthetic fixtures only. Run each trial under memory-watchdog.py.
defmodule Bylaw.Contract.QA.MemoryLifecycle do
  alias Bylaw.Contract.{Check, Specs, StructuralCoverage}

  @doc false
  @spec run(arguments :: list(String.t())) :: :ok
  def run([mode, speed | numbers]) do
    {numbers, [output | extra]} = Enum.split(numbers, 7)
    true = extra in [[], ["return_payload"]]
    return_payload? = extra == ["return_payload"]

    [module_count, functions, depth, payload, producers, calls, cycles] =
      Enum.map(numbers, &String.to_integer/1)

    true = module_count in 1..16 and functions in 1..16 and depth in 0..12
    true = payload in 0..2048 and producers in 1..4 and calls in 1..1000 and cycles in 1..3
    true = speed in ["running", "slow2", "slow10", "paused"]

    checks =
      case mode do
        "baseline" -> []
        "typespec" -> [Check.Typespec]
        "structural" -> [Check.FunctionClauses]
        "default" -> [Check.Typespec, Check.FunctionClauses]
      end

    modules = for index <- 1..module_count, do: Module.concat(__MODULE__, "Fixture#{index}")
    directory = output <> ".fixture"
    sampler = spawn_link(fn -> sample_loop("initial", [self()]) end)
    File.mkdir_p!(directory)

    result =
      try do
        measure(sampler, "fixture_compile", [], fn ->
          compile_fixtures(modules, functions, depth, directory, return_payload?)
        end)

        Code.prepend_path(directory)
        argument_sizes = preflight(sampler, modules, checks)

        results =
          for cycle <- 1..cycles do
            result =
              cycle(
                sampler,
                modules,
                functions,
                payload,
                producers,
                calls,
                checks,
                speed,
                directory,
                cycle,
                return_payload?,
                argument_sizes
              )

            :erlang.garbage_collect()

            measure(sampler, "cleanup_#{cycle}", [], fn ->
              Process.sleep(40)

              if return_payload?,
                do:
                  emit(%{
                    kind: "allocator_cleanup",
                    cycle: cycle,
                    allocators: allocator_sizes(),
                    segments: segment_sizes()
                  })
            end)

            result
          end

        if Enum.any?(checks) do
          [_] = results |> Enum.map(& &1.coverage_hash) |> Enum.uniq()
          [_] = results |> Enum.map(& &1.report_hash) |> Enum.uniq()
        end

        result = %{
          status: :complete,
          elixir: System.version(),
          otp: System.otp_release(),
          config: %{
            mode: mode,
            speed: speed,
            modules: module_count,
            functions: functions,
            depth: depth,
            payload: payload,
            producers: producers,
            calls: calls,
            cycles: cycles,
            return_payload: return_payload?
          },
          cycles: results
        }

        result
      after
        for module <- modules do
          :code.delete(module)
          :code.purge(module)
        end

        Code.delete_path(directory)
        File.rm_rf!(directory)

        measure(sampler, "fixture_cleanup", [], fn ->
          :erlang.garbage_collect()
          Process.sleep(40)
        end)

        send(sampler, :stop)
      end

    File.write!(output, :erlang.term_to_binary(result, [:compressed]))
    emit(Map.delete(result, :cycles))
  end

  defp preflight(sampler, modules, checks) do
    if Check.Typespec in checks do
      measure(sampler, "typespec_metadata", [], fn -> Specs.load(modules) |> sizes() |> emit() end)
    end

    if Check.FunctionClauses in checks do
      structural_preflight(sampler, modules)
    end

    {arguments, _claims} =
      Enum.map_reduce(checks, MapSet.new(), fn check, claims ->
        argument_size =
          Map.merge(sizes({modules, check, [], claims}), %{
            kind: "worker_start_arguments",
            check: inspect(check)
          })

        interests =
          measure(sampler, "direct_init_#{inspect(check)}", [], fn ->
            {:ok, state, interests} = check.init(modules, [], %{claims: claims})

            try do
              emit(sizes(state))
              interests
            after
              check.terminate(state)
            end
          end)

        :erlang.garbage_collect()
        {argument_size, MapSet.union(claims, interests.claims)}
      end)

    arguments
  end

  defp structural_preflight(sampler, modules) do
    loaded =
      measure(sampler, "structural_metadata", [], fn -> StructuralCoverage.load(modules) end)

    emit(sizes(loaded))

    shadow =
      measure(sampler, "shadow_compile", [], fn ->
        {:ok, shadow} = StructuralCoverage.start_shadow(loaded.classifiers)
        shadow
      end)

    measure(sampler, "shadow_cleanup", [], fn -> StructuralCoverage.stop_shadow(shadow) end)
  end

  defp cycle(
         sampler,
         modules,
         functions,
         payload_size,
         producers,
         calls,
         checks,
         speed,
         directory,
         cycle,
         return_payload?,
         argument_sizes
       ) do
    observer =
      measure(sampler, "worker_start_#{cycle}", [], fn ->
        if Enum.any?(checks) do
          {:ok, observer} = Bylaw.Contract.start(modules, checks: checks)
          observer
        end
      end)

    workers = if observer, do: :sys.get_state(observer).workers, else: []
    sessions = for worker <- workers, do: :sys.get_state(worker).session

    Enum.each(argument_sizes, &emit/1)

    for worker <- workers do
      parent = self()

      :sys.replace_state(worker, fn state ->
        send(parent, {:worker_sizes, sizes(state.runtime.state)})
        state
      end)

      receive do
        {:worker_sizes, data} -> emit(Map.put(data, :kind, "worker_retained"))
      end
    end

    payload = Enum.to_list(1..payload_size//1)

    targets =
      for module <- modules,
          function <- 1..functions,
          do: {module, String.to_atom("consume#{function}")}

    expected = Enum.frequencies(for index <- 0..(calls - 1), do: elem_at(targets, index))
    controller = start_controller(workers, speed)

    coverage =
      try do
        measure(sampler, "observation_#{cycle}", workers, fn ->
          tasks =
            for producer <- 0..(producers - 1) do
              Task.async(fn ->
                for index <- 0..(calls - 1), rem(index, producers) == producer do
                  {module, function} = elem_at(targets, index)

                  case {return_payload?, apply(module, function, [payload])} do
                    {false, ^payload_size} -> payload_size
                    {true, {:ok, ^payload}} -> :ok
                  end
                end
              end)
            end

          Enum.each(tasks, &Task.await(&1, 5000))

          for session <- sessions do
            ref = :trace.delivered(session, :all)

            receive do
              {:trace_delivered, :all, ^ref} -> :ok
            after
              2000 -> raise "delivery timeout"
            end
          end
        end)

        stop_controller(controller, workers, speed)

        measure(sampler, "stop_drain_#{cycle}", workers, fn ->
          if observer, do: Bylaw.Contract.stop(observer)
        end)
      after
        stop_controller(controller, workers, speed)
        if observer && Process.alive?(observer), do: Bylaw.Contract.stop(observer)
      end

    true = Enum.all?(workers, &(not Process.alive?(&1)))

    if coverage do
      for {{module, function}, count} <- expected do
        mfa = {module, function, 1}

        if Check.Typespec in checks do
          true = coverage.calls[mfa] == count
          if return_payload?, do: true = coverage.return_events[mfa] == count
        end

        if Check.FunctionClauses in checks, do: true = coverage.arity_calls[mfa] == count
      end

      summary =
        measure(sampler, "summary_#{cycle}", [], fn -> Bylaw.Contract.summary(coverage) end)

      report =
        measure(sampler, "report_#{cycle}", [], fn ->
          {:ok, io} = StringIO.open("")

          try do
            :ok = Bylaw.Contract.print_report(coverage, io)
            {_, report} = StringIO.contents(io)
            report
          after
            StringIO.close(io)
          end
        end)

      encoding =
        measure(sampler, "etf_encode_#{cycle}", [], fn ->
          encoded = :erlang.term_to_binary(coverage, [:deterministic])
          %{bytes: byte_size(encoded), decoded_equal: :erlang.binary_to_term(encoded) == coverage}
        end)

      true = encoding.decoded_equal

      %{
        coverage_hash: hash(normalize(coverage, directory)),
        report_hash: hash(String.replace(report, directory, "<fixture>")),
        coverage_sizes: sizes(coverage),
        summary: summary,
        encoding: encoding,
        workers_dead: true
      }
    else
      %{baseline_calls: calls, workers_dead: true}
    end
  end

  defp elem_at(targets, index), do: Enum.at(targets, rem(index, length(targets)))

  defp start_controller(workers, "paused") do
    Enum.each(workers, &:sys.suspend/1)
    nil
  end

  defp start_controller(_workers, "running"), do: nil

  defp start_controller(workers, speed) do
    delay = if speed == "slow2", do: 2, else: 10
    parent = self()

    pid =
      spawn_link(fn ->
        Enum.each(workers, &:sys.suspend/1)
        send(parent, {:controller_ready, self()})
        control(workers, delay)
      end)

    receive do
      {:controller_ready, ^pid} -> pid
    end
  end

  defp control(workers, delay) do
    receive do
      {:stop, caller} ->
        Enum.each(workers, &:sys.resume/1)
        send(caller, {:controller_stopped, self()})
    after
      delay ->
        Enum.each(workers, &:sys.resume/1)

        receive do
          {:stop, caller} -> send(caller, {:controller_stopped, self()})
        after
          2 ->
            Enum.each(workers, &:sys.suspend/1)
            control(workers, delay)
        end
    end
  end

  defp stop_controller(nil, workers, "paused"),
    do: Enum.each(workers, fn worker -> if Process.alive?(worker), do: :sys.resume(worker) end)

  defp stop_controller(nil, _workers, _speed), do: :ok

  defp stop_controller(controller, _workers, _speed) do
    if Process.alive?(controller) do
      send(controller, {:stop, self()})

      receive do
        {:controller_stopped, ^controller} -> :ok
      after
        2000 -> raise "controller timeout"
      end
    end
  end

  defp compile_fixtures(modules, functions, depth, directory, return_payload?) do
    paths =
      for module <- modules do
        aliases = for index <- 1..depth//1, do: "@type t#{index} :: t#{index - 1}()"

        definitions =
          for index <- 1..functions do
            if return_payload? do
              "@spec consume#{index}(list(t#{depth}())) :: {:ok, list(t#{depth}())} | {:error, :bad}\ndef consume#{index}(values), do: {:ok, values}"
            else
              "@spec consume#{index}(list(t#{depth}())) :: non_neg_integer()\ndef consume#{index}(values), do: length(values)"
            end
          end

        path = Path.join(directory, "#{module}.ex")

        File.write!(
          path,
          "defmodule #{inspect(module)} do\n@type t0 :: integer()\n#{Enum.join(aliases, "\n")}\n#{Enum.join(definitions, "\n")}\nend"
        )

        path
      end

    options = Code.compiler_options()

    try do
      Code.compiler_options(debug_info: true)

      {:ok, _, _} =
        Kernel.ParallelCompiler.compile_to_path(paths, directory, return_diagnostics: true)
    after
      Code.compiler_options(options)
    end
  end

  defp segment_sizes do
    for {:instance, _, entries} <- :erlang.system_info({:allocator, :mseg_alloc}),
        {:memkind, kind} <- entries,
        reduce: %{cached_segments: 0, segment_bytes: 0} do
      totals ->
        status = Keyword.fetch!(kind, :status)
        {:segments_size, current, _, _} = List.keyfind(status, :segments_size, 0)

        %{
          cached_segments: totals.cached_segments + Keyword.fetch!(status, :cached_segments),
          segment_bytes: totals.segment_bytes + current
        }
    end
  end

  defp allocator_sizes do
    Map.new(
      [
        :eheap_alloc,
        :binary_alloc,
        :ets_alloc,
        :ll_alloc,
        :std_alloc,
        :sl_alloc,
        :temp_alloc,
        :fix_alloc
      ],
      fn allocator ->
        totals =
          Enum.reduce(
            :erlang.system_info({:allocator_sizes, allocator}),
            %{blocks: 0, carriers: 0},
            fn
              {:instance, _, pools}, totals ->
                Enum.reduce(pools, totals, fn {_pool, entries}, totals ->
                  Enum.reduce(entries, totals, fn
                    {:carriers_size, current, _, _}, totals ->
                      %{totals | carriers: totals.carriers + current}

                    {:blocks, blocks}, totals ->
                      size =
                        for {_type, sizes} <- blocks,
                            {:size, current, _, _} <- sizes,
                            reduce: 0 do
                          sum -> sum + current
                        end

                      %{totals | blocks: totals.blocks + size}

                    _, totals ->
                      totals
                  end)
                end)
            end
          )

        {allocator, totals}
      end
    )
  end

  defp sizes(term),
    do: %{
      shared_bytes: :erts_debug.size(term) * :erlang.system_info(:wordsize),
      flat_bytes: :erts_debug.flat_size(term) * :erlang.system_info(:wordsize),
      stored_nodes: nodes(term)
    }

  defp nodes(term) when is_map(term),
    do: 1 + Enum.sum(for {k, v} <- :maps.to_list(term), do: nodes(k) + nodes(v))

  defp nodes(term) when is_tuple(term), do: 1 + nodes(Tuple.to_list(term))
  defp nodes([]), do: 1
  defp nodes([h | t]), do: 1 + nodes(h) + nodes(t)
  defp nodes(_), do: 1

  defp hash(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic])) |> Base.encode16()

  defp normalize(term, directory) when is_binary(term),
    do: String.replace(term, directory, "<fixture>")

  defp normalize(term, directory) when is_map(term),
    do:
      Map.new(:maps.to_list(term), fn {k, v} ->
        {normalize(k, directory), normalize(v, directory)}
      end)

  defp normalize(term, directory) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(&normalize(&1, directory)) |> List.to_tuple()

  defp normalize(term, directory) when is_list(term),
    do: Enum.map(term, &normalize(&1, directory))

  defp normalize(term, _directory), do: term

  defp measure(sampler, label, workers, function) do
    set_phase(sampler, label, [self() | workers])
    {us, result} = :timer.tc(function)
    set_phase(sampler, label, [self() | workers])
    emit(%{duration_us: us, phase: label})
    set_phase(sampler, "between_phases", [])
    result
  end

  defp set_phase(sampler, label, workers) do
    send(sampler, {:phase, label, workers, self()})

    receive do
      {:sampled, ^sampler} -> :ok
    after
      2000 -> raise "sampler timeout"
    end
  end

  defp sample_loop(phase, workers) do
    sample(phase, workers)

    receive do
      :stop ->
        :ok

      {:phase, label, workers, caller} ->
        sample(label, workers)
        send(caller, {:sampled, self()})
        sample_loop(label, workers)
    after
      20 -> sample_loop(phase, workers)
    end
  end

  defp sample(phase, workers) do
    memory = Map.new(:erlang.memory())

    emit(%{
      phase: phase,
      wall_us: System.system_time(:microsecond),
      beam: memory,
      processes:
        Enum.map(workers, fn p ->
          Map.new(Process.info(p, [:memory, :message_queue_len]) || [])
        end)
    })

    if memory.total > 384 * 1024 * 1024 do
      emit(%{status: :incomplete_beam_budget})
      System.halt(86)
    end
  end

  defp emit(data), do: IO.puts(JSON.encode!(data))
end

Bylaw.Contract.QA.MemoryLifecycle.run(System.argv())
