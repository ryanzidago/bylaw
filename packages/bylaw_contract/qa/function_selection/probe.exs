[project, ebin, output] = System.argv()
Code.prepend_path(ebin)

{module, function, inputs, expected} =
  case project do
    "ecto" ->
      uuid = "00000000-0000-0000-0000-000000000000"

      {Ecto.UUID, :cast, [uuid, <<0::128>>, "invalid", :invalid],
       [{:ok, uuid}, {:ok, uuid}, :error, :error]}

    "livebook" ->
      {Livebook.Text.Delta.Operation, :from_compressed, ["text", 0, 3, -5],
       [{:insert, "text"}, {:retain, 0}, {:retain, 3}, {:delete, 5}]}
  end

Code.ensure_loaded!(module)
^expected = Enum.map(inputs, &apply(module, function, [&1]))
mfa = {module, function, 1}
md5 = module.module_info(:md5)

fields = [
  :input_classes,
  :boundaries,
  :return_alternatives,
  :clauses,
  :arities,
  :compiler_return_alternatives
]

counters = [:calls, :return_events, :arity_calls, :compiler_calls]

checks = [
  Bylaw.Contract.Check.Typespec,
  Bylaw.Contract.Check.FunctionClauses,
  Bylaw.Contract.Check.ElixirCompiler
]

observe = fn check, scope ->
  options = if scope == :all, do: [checks: [check]], else: [checks: [check], only: [mfa]]
  {:ok, tracer} = Bylaw.Contract.start([module], options)
  workers = :sys.get_state(tracer).workers

  try do
    ^expected = Enum.map(inputs, &apply(module, function, [&1]))

    ^expected =
      Task.async(fn -> Enum.map(inputs, &apply(module, function, [&1])) end) |> Task.await()

    coverage = Bylaw.Contract.stop(tracer)
    true = module.module_info(:md5) == md5
    true = Enum.all?(workers, &(not Process.alive?(&1)))
    false = Map.get(coverage, :status) == :incomplete
    coverage
  after
    if Process.alive?(tracer), do: Bylaw.Contract.stop(tracer)
  end
end

results =
  for check <- checks do
    baseline = observe.(check, :all)

    selected_targets =
      Map.new(fields, fn field ->
        {field,
         Enum.filter(Map.fetch!(baseline, field), &({&1.module, &1.function, &1.arity} == mfa))}
      end)

    ids =
      selected_targets
      |> Map.values()
      |> List.flatten()
      |> Enum.flat_map(fn target ->
        if Map.has_key?(target, :id), do: [target.id], else: []
      end)
      |> MapSet.new()

    runs =
      for _ <- 1..3 do
        scoped = observe.(check, :selected)

        for field <- fields,
            do: true = Map.fetch!(scoped, field) == Map.fetch!(selected_targets, field)

        for field <- counters do
          true =
            Map.get(Map.fetch!(scoped, field), mfa, 0) ==
              Map.get(Map.fetch!(baseline, field), mfa, 0)

          true = Enum.all?(Map.keys(Map.fetch!(scoped, field)), &(&1 == mfa))
        end

        for field <- [:hits, :clause_outcomes] do
          true =
            Map.fetch!(scoped, field) ==
              Map.take(Map.fetch!(baseline, field), MapSet.to_list(ids))
        end

        true = scoped.unknown == MapSet.intersection(baseline.unknown, ids)

        %{
          counters:
            Map.new(counters, &{Atom.to_string(&1), Map.get(Map.fetch!(scoped, &1), mfa, 0)}),
          targets: Map.new(fields, &{Atom.to_string(&1), length(Map.fetch!(scoped, &1))}),
          unknown: MapSet.size(scoped.unknown),
          warnings: scoped.warnings,
          compiler_warnings: scoped.compiler_warnings,
          complete: true,
          restored: true
        }
      end

    %{check: inspect(check), runs: runs}
  end

{:ok, empty} = Bylaw.Contract.start([module], checks: checks, only: [])
[] = :sys.get_state(empty).workers
%{selected_functions: []} = Bylaw.Contract.stop(empty)

File.write!(
  output,
  :json.encode(%{
    project: project,
    module: inspect(module),
    function: function,
    elixir: System.version(),
    otp: System.otp_release(),
    results: results
  })
  |> IO.iodata_to_binary()
)

IO.puts(
  "#{project}: full/selected target identities, counters, unknown outcomes and three restoration cycles match"
)
