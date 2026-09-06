# Diagnostic only. Load after performance-phase-probe.exs in a fresh command VM.
# Measure reachable state inside its owner; never copy the prepared term elsewhere.
defmodule BylawPreparationStateProbe do
  @moduledoc false

  @doc false
  @spec record(atom(), map()) :: :ok
  def record(phase, state) do
    {:memory, process_bytes} = Process.info(self(), :memory)
    {:message_queue_len, queue_length} = Process.info(self(), :message_queue_len)

    row = %{
      phase: phase,
      check: inspect(state.runtime.module),
      at_us: System.monotonic_time(:microsecond),
      process_bytes: process_bytes,
      queue_length: queue_length,
      reachable_check_state_bytes:
        :erts_debug.size(state.runtime.state) * :erlang.system_info(:wordsize)
    }

    :ets.insert(__MODULE__, {System.unique_integer([:positive]), row})
    :ok
  end
end

caller = self()

owner =
  spawn(fn ->
    :ets.new(BylawPreparationStateProbe, [:named_table, :public, :ordered_set])
    send(caller, :state_table_ready)

    receive do
      {:snapshot, recipient} ->
        send(recipient, {:prepared_states, :ets.tab2list(BylawPreparationStateProbe)})
    end
  end)

receive do: (:state_table_ready -> :ok)
path = Path.expand("../lib/bylaw/contract/trace_worker.ex", __DIR__)
ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

ast =
  Macro.prewalk(ast, fn
    {kind, metadata, [{name, _, arguments} = head, [do: body]]}
    when kind in [:def, :defp] and name in [:init, :start_runtime, :stop_trace] ->
      wrapped =
        case name do
          :init ->
            quote do
              result = unquote(body)

              case result do
                {:ok, state} -> BylawPreparationStateProbe.record(:prepared, state)
                _ -> :ok
              end

              result
            end

          name ->
            label = {"trace_worker.ex", name, length(arguments)}

            quote do
              BylawPerformancePhaseProbe.measure(unquote(Macro.escape(label)), fn ->
                unquote(
                  if name == :stop_trace do
                    quote do
                      BylawPreparationStateProbe.record(:before_stop, unquote(hd(arguments)))
                    end
                  end
                )

                unquote(body)
              end)
            end
        end

      {kind, metadata, [head, [do: wrapped]]}

    other ->
      other
  end)

options = Code.compiler_options(ignore_module_conflict: true)
Code.compile_quoted(ast, path)
Code.compiler_options(options)

System.at_exit(fn _ ->
  send(owner, {:snapshot, self()})

  receive do
    {:prepared_states, rows} ->
      File.write!(
        System.fetch_env!("BYLAW_PREPARED_STATE_OUTPUT"),
        JSON.encode!(Enum.map(rows, &elem(&1, 1))) <> "\n"
      )
  after
    5_000 -> raise "prepared-state collector did not respond"
  end
end)
