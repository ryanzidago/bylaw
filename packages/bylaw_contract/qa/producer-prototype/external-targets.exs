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

result =
  case ProducerTargetPlan.compile(entries) do
    {:error, reason} ->
      %{observation_status: :not_started, reason: inspect(reason)}

    {:ok, plan} ->
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

      cycles =
        for cycle <- 1..3 do
          resource = ProducerNative.plan(plan.rules, 4096)

          session =
            :trace.session_create(:producer_external_targets, {ProducerNative, resource}, [])

          try do
            for mfa <- plan.mfas do
              1 = :trace.function(session, mfa, [{:_, [], [{:return_trace}]}], [:local])
            end

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

      %{observation_status: :complete, target_count: map_size(plan.slots), cycles: cycles}
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
