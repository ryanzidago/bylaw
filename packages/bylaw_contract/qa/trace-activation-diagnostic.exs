defmodule BylawTraceActivationDiagnostic do
  @moduledoc false

  @doc false
  @spec measure(atom(), (-> term()), map()) :: term()
  def measure(name, function, details) do
    {before_calls, before_us} = Process.get(__MODULE__, {0, 0})
    started = System.monotonic_time(:microsecond)

    try do
      function.()
    after
      finished = System.monotonic_time(:microsecond)
      {after_calls, after_us} = Process.get(__MODULE__, {0, 0})

      :ets.insert(__MODULE__, {
        System.unique_integer([:positive]),
        %{
          function: name,
          pid: inspect(self()),
          started_us: started,
          finished_us: finished,
          duration_us: finished - started,
          install_calls: after_calls - before_calls,
          install_us: after_us - before_us,
          details: details
        }
      })
    end
  end

  @doc false
  @spec install(term(), tuple(), term(), list(atom())) :: non_neg_integer()
  def install(session, mfa, match_spec, flags) do
    started = System.monotonic_time(:microsecond)

    try do
      :trace.function(session, mfa, match_spec, flags)
    after
      elapsed = System.monotonic_time(:microsecond) - started
      {calls, time} = Process.get(__MODULE__, {0, 0})
      Process.put(__MODULE__, {calls + 1, time + elapsed})
    end
  end
end

caller = self()

owner =
  spawn(fn ->
    :ets.new(BylawTraceActivationDiagnostic, [:named_table, :public, :ordered_set])
    send(caller, :activation_collector_ready)

    receive do
      {:snapshot, recipient} ->
        send(recipient, {:activation_spans, :ets.tab2list(BylawTraceActivationDiagnostic)})
    end
  end)

receive do: (:activation_collector_ready -> :ok)

path = Path.expand("../lib/bylaw/contract/trace_worker.ex", __DIR__)
ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

names = [
  :start_runtime,
  :start_process_worker,
  :start_trace_session,
  :create_session,
  :configure_session,
  :configure_patterns,
  :configure_process_scope,
  :stop_trace
]

instrumented =
  Macro.postwalk(ast, fn
    {{:., metadata, [:trace, :function]}, call_metadata, arguments} ->
      {{:., metadata, [{:__aliases__, [], [:BylawTraceActivationDiagnostic]}, :install]},
       call_metadata, arguments}

    {{:., _, [{:__aliases__, _, [:TraceQueueBudget]}, :start]}, _, arguments} = call ->
      3 = length(arguments)

      quote do
        BylawTraceActivationDiagnostic.measure(:queue_budget_start, fn -> unquote(call) end, %{})
      end

    {kind, metadata, [head, body_clauses]} = definition
    when kind in [:def, :defp] and is_list(body_clauses) ->
      call =
        case head do
          {:when, _, [call | _]} -> call
          call -> call
        end

      {name, _, _arguments} = call

      if name in names do
        body =
          if Keyword.keys(body_clauses) == [:do],
            do: Keyword.fetch!(body_clauses, :do),
            else: {:try, [], [body_clauses]}

        details =
          if name == :configure_patterns do
            calls = Macro.var(:call_mfas, nil)
            returns = Macro.var(:return_mfas, nil)
            scope = Macro.var(:trace_scope, nil)

            quote do
              %{
                calls: MapSet.size(unquote(calls)),
                returns: MapSet.size(unquote(returns)),
                patterns: MapSet.size(MapSet.union(unquote(calls), unquote(returns))),
                scope: Atom.to_string(unquote(scope))
              }
            end
          else
            quote do: %{}
          end

        wrapped =
          quote do
            BylawTraceActivationDiagnostic.measure(
              unquote(name),
              fn -> unquote(body) end,
              unquote(details)
            )
          end

        {kind, metadata, [head, [do: wrapped]]}
      else
        definition
      end

    node ->
      node
  end)

options = Code.compiler_options()

try do
  Code.compiler_options(ignore_module_conflict: true)
  Code.compile_quoted(instrumented, path)
after
  Code.compiler_options(Map.to_list(options))
end

System.at_exit(fn _ ->
  send(owner, {:snapshot, self()})

  entries =
    receive do
      {:activation_spans, entries} -> entries
    after
      5_000 -> raise "activation collector did not respond"
    end

  spans = Enum.map(entries, &elem(&1, 1))
  File.write!(System.fetch_env!("BYLAW_TRACE_PHASE_OUTPUT"), JSON.encode!(spans) <> "\n")
end)
