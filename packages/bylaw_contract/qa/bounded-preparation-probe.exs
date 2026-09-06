Code.prepend_path(System.fetch_env!("BYLAW_OVERHEAD_EBIN"))
Code.require_file("bounded-preparation.exs", __DIR__)

defmodule BylawBoundedPreparationProbe do
  @moduledoc false

  @doc false
  @spec run(list(module()), map() | nil, module() | tuple()) :: map()
  def run(modules, fixture, check) do
    Enum.each(modules, &Code.ensure_loaded!/1)
    sources = Map.new(modules, &{inspect(&1), Base.encode16(&1.module_info(:md5))})
    before_start = memory()

    {start_us, {:ok, observer}} =
      :timer.tc(fn -> Bylaw.Contract.start(modules, checks: [check]) end)

    try do
      after_start = memory()
      active_shadows = shadows()
      {workload_us, _} = :timer.tc(fn -> if fixture, do: workload(modules, fixture) end)
      before_stop = memory()
      {stop_us, coverage} = :timer.tc(fn -> Bylaw.Contract.stop(observer) end)
      after_stop = memory()
      complete = Map.get(coverage, :status, :complete) == :complete
      if fixture, do: oracle(coverage, modules, fixture)
      normalized = normalize(coverage)
      {:ok, io} = StringIO.open("")
      {report_us, _} = :timer.tc(fn -> Bylaw.Contract.Report.print(coverage, io, false) end)
      {_, report} = StringIO.contents(io)
      StringIO.close(io)

      {cleanup_wait_us, []} =
        :timer.tc(fn -> await_workers(System.monotonic_time(:millisecond) + 2_000) end)

      true = Enum.empty?(shadows())
      [legacy: :default] = :trace.session_info(:all)
      ^sources = Map.new(modules, &{inspect(&1), Base.encode16(&1.module_info(:md5))})

      %{
        start_us: start_us,
        workload_us: workload_us,
        stop_us: stop_us,
        report_us: report_us,
        before_start: before_start,
        after_start: after_start,
        before_stop: before_stop,
        after_stop: after_stop,
        active_units: length(active_shadows),
        clauses: length(coverage.clauses),
        arities: length(coverage.arities),
        modules: length(coverage.structural_modules),
        complete: complete,
        incomplete: inspect(Map.get(coverage, :incomplete, [])),
        source_md5s: sources,
        coverage_sha256: fingerprint(normalized),
        report_sha256: :crypto.hash(:sha256, report) |> Base.encode16(),
        fixture_oracle: fixture != nil,
        cleanup_wait_us: cleanup_wait_us,
        cleanup: true
      }
    after
      if Process.alive?(observer), do: Bylaw.Contract.stop(observer)
    end
  end

  defp workload(modules, fixture) do
    for module <- modules, function <- 1..fixture["functions"], value <- [-1, 0, 1, 10, :atom] do
      expected =
        if is_integer(value) and value >= 0,
          do: {max(1, fixture["clauses"] - 1 - value), :default},
          else: {:fallback, :default}

      ^expected = apply(module, String.to_atom("classify#{function}"), [value])
    end
  end

  defp oracle(coverage, modules, fixture) do
    :complete = Map.get(coverage, :status, :complete)
    true = length(coverage.clauses) == length(modules) * fixture["functions"] * fixture["clauses"]
    true = length(coverage.arities) == length(modules) * fixture["functions"] * 2

    for module <- modules, function <- 1..fixture["functions"], arity <- [1, 2] do
      5 = Map.fetch!(coverage.arity_calls, {module, String.to_atom("classify#{function}"), arity})
    end

    for clause <- coverage.clauses do
      expected =
        if clause.position == fixture["clauses"] do
          %{head_matches: 5, guard_passes: 5, guard_rejections: 0, selected: 2}
        else
          threshold = fixture["clauses"] - 1 - clause.position
          passes = Enum.count([0, 1, 10], &(&1 >= threshold))

          selected =
            Enum.count([0, 1, 10], fn value ->
              max(1, fixture["clauses"] - 1 - value) == clause.position
            end)

          %{
            head_matches: 5,
            guard_passes: passes,
            guard_rejections: 5 - passes,
            selected: selected
          }
        end

      ^expected = Map.fetch!(coverage.clause_outcomes, clause.id)
    end
  end

  defp normalize(coverage) do
    update_in(coverage.checks, fn checks ->
      case Map.pop(checks, BylawBoundedStructuralPreparation) do
        {nil, checks} -> checks
        {data, checks} -> Map.put(checks, Bylaw.Contract.Check.FunctionClauses, data)
      end
    end)
  end

  defp fingerprint(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  defp memory, do: Map.new(:erlang.memory([:total, :processes, :binary, :code, :ets]))

  defp await_workers(deadline) do
    workers =
      for pid <- Process.list(),
          {:dictionary, dictionary} <- [Process.info(pid, :dictionary)],
          Keyword.get(dictionary, :"$initial_call") in [
            {Bylaw.Contract.Tracer, :init, 1},
            {Bylaw.Contract.TraceWorker, :init, 1}
          ],
          do: pid

    if Enum.empty?(workers) or System.monotonic_time(:millisecond) >= deadline do
      workers
    else
      Process.sleep(1)
      await_workers(deadline)
    end
  end

  defp shadows do
    for {module, _} <- :code.all_loaded(),
        String.starts_with?(
          Atom.to_string(module),
          "Elixir.Bylaw.Contract.StructuralCoverage.Shadow"
        ),
        do: module
  end
end

fixture_path = System.get_env("BYLAW_BOUNDED_FIXTURE")
fixture = if fixture_path, do: fixture_path |> File.read!() |> JSON.decode!()

modules =
  if fixture do
    for index <- 1..fixture["modules"], do: Module.concat(BylawBoundedFixture, "Module#{index}")
  else
    app = System.fetch_env!("BYLAW_BOUNDED_APP") |> String.to_atom()
    Application.load(app)
    Application.spec(app, :modules)
  end

check =
  case System.fetch_env!("BYLAW_BOUNDED_UNITS") do
    "aggregate" -> Bylaw.Contract.Check.FunctionClauses
    size -> {BylawBoundedStructuralPreparation, unit_size: String.to_integer(size)}
  end

result = %{
  cycles:
    for(
      cycle <- ["first", "repeated"],
      do: BylawBoundedPreparationProbe.run(modules, fixture, check) |> Map.put(:cycle, cycle)
    )
}

File.write!(System.fetch_env!("BYLAW_BOUNDED_OUTPUT"), JSON.encode!(result) <> "\n")
