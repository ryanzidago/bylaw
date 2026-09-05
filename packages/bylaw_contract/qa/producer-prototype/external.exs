# Focused transport exercise against an explicitly supplied approved checkout.
[project, ebin, output] = System.argv()
Code.prepend_path(ebin)

{module, function, inputs, expected, flags, expected_hits} =
  case project do
    "ecto" ->
      uuid = "00000000-0000-0000-0000-000000000000"

      {Ecto.UUID, :cast, [uuid, <<0::128>>, "invalid", :invalid],
       [{:ok, uuid}, {:ok, uuid}, :error, :error], {{:is_binary, :"$1"}, {:is_atom, :"$1"}},
       [49152, 16384, 0, 0, 0, 0, 0, 0]}

    "livebook" ->
      {Livebook.Text.Delta.Operation, :from_compressed, ["text", 0, 3, -5],
       [{:insert, "text"}, {:retain, 0}, {:retain, 3}, {:delete, 5}],
       {{:is_binary, :"$1"}, {:andalso, {:is_integer, :"$1"}, {:>=, :"$1", 0}},
        {:andalso, {:is_integer, :"$1"}, {:<, :"$1", 0}}}, [16384, 32768, 16384, 0, 0, 0, 0, 0]}
  end

{:module, ^module} = Code.ensure_loaded(module)
^expected = Enum.map(inputs, &apply(module, function, [&1]))
md5 = module.module_info(:md5)

cycles =
  for cycle <- 1..3 do
    resource = ProducerNative.new()
    session = :trace.session_create(:producer_external, {ProducerNative, resource}, [])

    1 =
      :trace.function(
        session,
        {module, function, 1},
        [{[:"$1"], [], [{:message, {flags}}, {:return_trace}]}],
        [:local]
      )

    ProducerNative.watch_code_changes(session)
    :trace.process(session, :all, true, [:call])
    started = System.monotonic_time(:microsecond)
    parent = self()

    children =
      for _ <- 1..8 do
        spawn_monitor(fn ->
          for _ <- 1..2048 do
            ^expected = Enum.map(inputs, &apply(module, function, [&1]))
          end

          send(parent, {:done, self()})
        end)
      end

    for {pid, ref} <- children do
      receive do
        {:done, ^pid} -> :ok
      after
        10_000 -> raise "producer timeout"
      end

      receive do
        {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      after
        10_000 -> raise "producer failed"
      end
    end

    :trace.session_destroy(session)
    elapsed = System.monotonic_time(:microsecond) - started
    {65536, 65536} = ProducerNative.counts(resource)
    ^expected_hits = ProducerNative.hits(resource)
    :complete = ProducerNative.status(resource)
    ^md5 = module.module_info(:md5)

    try do
      :trace.info(session, {module, function, 1}, :traced)
      raise "session not destroyed"
    rescue
      ArgumentError -> :ok
    end

    %{
      cycle: cycle,
      calls: 65536,
      returns: 65536,
      hits: expected_hits,
      elapsed_us: elapsed,
      native_payload_bytes: ProducerNative.bytes(resource),
      transport_status: :complete,
      unchanged_results: true,
      unchanged_module_md5: true
    }
  end

File.write!(
  output,
  JSON.encode!(%{
    project: project,
    target: inspect({module, function, 1}),
    elixir: System.version(),
    otp: :erlang.system_info(:otp_release) |> List.to_string(),
    cycles: cycles
  })
)
