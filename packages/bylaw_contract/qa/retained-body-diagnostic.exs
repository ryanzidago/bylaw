# Separately labelled diagnostics only; never part of the unprofiled timing matrix.
defmodule BylawRetainedBodyDiagnostic do
  @moduledoc false

  @doc false
  @spec measure(atom(), (-> term())) :: term()
  def measure(name, function) do
    started = System.monotonic_time(:microsecond)

    try do
      function.()
    after
      elapsed = System.monotonic_time(:microsecond) - started
      :ets.insert(__MODULE__, {System.unique_integer([:positive]), name, elapsed})
    end
  end
end

caller = self()

owner =
  spawn(fn ->
    :ets.new(BylawRetainedBodyDiagnostic, [:named_table, :public, :ordered_set])
    send(caller, :diagnostic_ready)

    receive do
      {:snapshot, recipient} ->
        send(recipient, {:diagnostic_rows, :ets.tab2list(BylawRetainedBodyDiagnostic)})
    end
  end)

receive do: (:diagnostic_ready -> :ok)
path = System.fetch_env!("BYLAW_BODY_SOURCE")
options = Code.compiler_options()

names = [
  :load_module,
  :elixir_definitions,
  :abstract_forms,
  :extract_definition,
  :shadow_forms,
  :compile_forms
]

ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

ast =
  Macro.postwalk(ast, fn
    {kind, metadata, [head, [do: body]]} = definition when kind in [:def, :defp] ->
      call =
        case head do
          {:when, _, [call | _]} -> call
          call -> call
        end

      {name, _, _} = call

      if name in names do
        wrapped =
          quote do
            BylawRetainedBodyDiagnostic.measure(unquote(name), fn -> unquote(body) end)
          end

        {kind, metadata, [head, [do: wrapped]]}
      else
        definition
      end

    {{:., _, [:beam_lib, :chunks]}, _, _} = call ->
      quote do
        BylawRetainedBodyDiagnostic.measure(:beam_chunks, fn -> unquote(call) end)
      end

    other ->
      other
  end)

try do
  Code.compiler_options(ignore_module_conflict: true)
  Code.compile_quoted(ast, path)
after
  Code.compiler_options(options)
end

System.at_exit(fn _ ->
  send(owner, {:snapshot, self()})

  entries =
    receive do
      {:diagnostic_rows, entries} -> entries
    after
      5_000 -> raise "diagnostic collector did not respond"
    end

  rows =
    entries
    |> Enum.group_by(fn {_, name, _} -> name end)
    |> Map.new(fn {name, values} ->
      durations = Enum.map(values, fn {_, _, duration} -> duration end)

      {name,
       %{calls: length(values), total_us: Enum.sum(durations), maximum_us: Enum.max(durations)}}
    end)

  File.write!(System.fetch_env!("BYLAW_BODY_DIAGNOSTIC"), JSON.encode!(rows) <> "\n")
end)
