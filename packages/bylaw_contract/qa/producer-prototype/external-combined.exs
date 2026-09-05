[project, ebin, output] = System.argv()
Code.prepend_path(ebin)

{module, function, inputs, expected_results} =
  case project do
    "ecto" ->
      uuid = "00000000-0000-0000-0000-000000000000"

      {Ecto.UUID, :cast, [uuid, <<0::128>>, "invalid", :invalid],
       [{:ok, uuid}, {:ok, uuid}, :error, :error]}

    "livebook" ->
      {Livebook.Text.Delta.Operation, :from_compressed, ["text", 0, 3, -5],
       [{:insert, "text"}, {:retain, 0}, {:retain, 3}, {:delete, 5}]}
  end

{:module, ^module} = Code.ensure_loaded(module)
^expected_results = Enum.map(inputs, &apply(module, function, [&1]))
md5 = module.module_info(:md5)
loaded = Bylaw.Contract.Specs.load([module])
[] = loaded.warnings

entries =
  Enum.map(loaded.input_classes ++ loaded.boundaries, &{:call, &1}) ++
    Enum.map(loaded.return_alternatives, &{:return, &1})

entries =
  Enum.filter(entries, fn {_, target} ->
    {target.module, target.function, target.arity} == {module, function, 1}
  end)

structural = Bylaw.Contract.StructuralCoverage.load([module])
[] = structural.warnings
classifier = Enum.find(structural.classifiers, &(&1.module == module))
mfa_classifier = Enum.find(classifier.mfa_classifiers, &(&1.mfa == {module, function, 1}))

compiled =
  with {:ok, targets} <- ProducerTargetPlan.compile(entries),
       {:ok, clauses} <- ProducerClausePlan.compile(mfa_classifier) do
    {:ok, {targets, clauses}}
  end

result =
  case compiled do
    {:error, reason} ->
      %{observation_status: :not_started, reason: inspect(reason)}

    {:ok, {plan, clause_plan}} ->
      expected =
        Enum.reduce(entries, List.duplicate(0, 8), fn {event, target}, counts ->
          values = if event == :call, do: inputs, else: expected_results

          hits =
            Enum.count(values, fn value ->
              case Bylaw.Contract.TypeMatcher.match(value, target.match_type) do
                :match -> true
                :no_match -> false
                other -> raise "baseline classification failed: #{inspect(other)}"
              end
            end) * 16384

          List.replace_at(counts, Map.fetch!(plan.slots, target.id), hits)
        end)

      {:ok, shadow} = Bylaw.Contract.StructuralCoverage.start_shadow(structural.classifiers)

      descriptor = %{
        classifier_function: classifier.classifier_function,
        source_function: function,
        source_arity: 1
      }

      baseline =
        try do
          Enum.map(
            inputs,
            &Bylaw.Contract.StructuralCoverage.classify(shadow, descriptor, [&1], self())
          )
        after
          Bylaw.Contract.StructuralCoverage.stop_shadow(shadow)
        end

      clause_count = map_size(clause_plan.slots)

      clause_expected =
        Enum.reduce(baseline, List.duplicate(0, clause_count), fn {selected, outcomes}, counts ->
          flags =
            for {{head, guard}, position} <- Enum.with_index(outcomes, 1), reduce: [] do
              acc -> acc ++ [head, guard, selected == position, head and not guard]
            end

          Enum.zip_with(counts, flags, fn count, flag -> count + if(flag, do: 16384, else: 0) end)
        end)

      expected = Enum.take(expected, length(plan.rules)) ++ clause_expected
      expected = expected ++ List.duplicate(0, max(0, 8 - length(expected)))

      cycles =
        for cycle <- 1..3 do
          resource = ProducerNative.plan(plan.rules, 4096, clause_count)

          session =
            :trace.session_create(:producer_external_combined, {ProducerNative, resource}, [])

          try do
            [mfa] = plan.mfas
            ^mfa = clause_plan.mfa
            1 = :trace.function(session, mfa, clause_plan.match_spec, [:local])

            ProducerNative.watch_code_changes(session)
            :trace.process(session, :all, true, [:call])
            parent = self()

            for _ <- 1..8 do
              spawn(fn ->
                for index <- 0..8191 do
                  value = Enum.at(inputs, rem(index, 4))
                  expected_result = Enum.at(expected_results, rem(index, 4))
                  ^expected_result = apply(module, function, [value])
                end

                send(parent, :clauses_done)
              end)
            end

            for _ <- 1..8 do
              receive do
                :clauses_done -> :ok
              after
                15_000 -> raise "producer timeout"
              end
            end
          after
            :trace.session_destroy(session)
          end

          {65536, 65536} = ProducerNative.counts(resource)
          ^expected = ProducerNative.hits(resource)
          :complete = ProducerNative.status(resource)
          ^md5 = module.module_info(:md5)

          %{
            cycle: cycle,
            calls: 65536,
            returns: 65536,
            hits: expected,
            native_payload_bytes: ProducerNative.bytes(resource),
            observation_status: :complete,
            unchanged_results: true,
            unchanged_module_md5: true
          }
        end

      %{
        observation_status: :complete,
        target_count: map_size(plan.slots),
        clause_counter_count: clause_count,
        cycles: cycles
      }
  end

record =
  Map.merge(result, %{
    project: project,
    target: inspect({module, function, 1}),
    elixir: System.version(),
    otp: :erlang.system_info(:otp_release) |> List.to_string()
  })

File.write!(output, JSON.encode!(record))
IO.puts(File.read!(output))
