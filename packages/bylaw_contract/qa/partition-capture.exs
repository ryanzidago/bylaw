# QA-only envelope around the existing ordinary native-Mix capture.
Application.load(:ex_unit)

Application.put_env(
  :ex_unit,
  :failures_manifest_path,
  System.fetch_env!("BYLAW_PARTITION_FAILURES")
)

defmodule BylawPartitionCapture do
  @moduledoc false
  use GenServer

  @impl GenServer
  def init(options) do
    {:ok, delegate} = BylawPreparationCapture.init(options)
    bootstrap = String.to_integer(System.fetch_env!("BYLAW_PARTITION_BOOTSTRAP"))

    if bootstrap == 1 do
      apply(BylawPhaseFixture.Classifier1, :classify, [1])
    end

    {:ok, %{delegate: delegate, inventory: [], bootstrap: bootstrap}}
  end

  @impl GenServer
  def handle_cast({:test_finished, test} = event, state) do
    identity = [
      Path.expand(test.tags.file),
      inspect(test.module),
      Atom.to_string(test.name),
      test.tags.line
    ]

    {:noreply, delegate} = BylawPreparationCapture.handle_cast(event, state.delegate)
    {:noreply, %{state | delegate: delegate, inventory: [identity | state.inventory]}}
  end

  def handle_cast({:suite_finished, _} = event, state) do
    {:noreply, delegate} = BylawPreparationCapture.handle_cast(event, state.delegate)
    path = System.fetch_env!("BYLAW_OVERHEAD_OUTPUT")
    capture = path |> File.read!() |> :erlang.binary_to_term()

    envelope =
      Map.merge(capture, %{
        schema: 1,
        runtime: %{elixir: System.version(), erts: to_string(:erlang.system_info(:version))},
        run_id: System.fetch_env!("BYLAW_PARTITION_RUN_ID"),
        source_fingerprint: System.fetch_env!("BYLAW_PARTITION_FINGERPRINT"),
        partition_id: String.to_integer(System.fetch_env!("MIX_TEST_PARTITION")),
        partition_total: String.to_integer(System.fetch_env!("BYLAW_PARTITION_TOTAL")),
        iterations: String.to_integer(System.fetch_env!("BYLAW_PARTITION_ITERATIONS")),
        bootstrap_calls: state.bootstrap,
        test_inventory: Enum.sort(state.inventory)
      })

    File.write!(path, :erlang.term_to_binary(envelope))
    {:noreply, %{state | delegate: delegate}}
  end

  def handle_cast(event, state) do
    {:noreply, delegate} = BylawPreparationCapture.handle_cast(event, state.delegate)
    {:noreply, %{state | delegate: delegate}}
  end

  @impl GenServer
  def terminate(reason, state), do: BylawPreparationCapture.terminate(reason, state.delegate)
end
