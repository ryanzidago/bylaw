[fixture, output] = System.argv()
config = fixture |> File.read!() |> JSON.decode!()
modules = Enum.map(config["modules"], &String.to_atom/1)
Enum.each(modules, &Code.ensure_loaded!/1)
mfas = for module <- modules, function <- 1..64, do: {module, String.to_atom("f#{function}"), 1}

rows =
  for trial <- 1..3,
      concurrency <- Enum.drop([1, 2, 4, 8], trial - 1) ++ Enum.take([1, 2, 4, 8], trial - 1) do
    collector =
      spawn(fn ->
        loop = fn loop, events ->
          receive do
            {:trace, caller, :call, {module, function, arguments}} ->
              loop.(loop, [{caller, module, function, arguments} | events])

            {:snapshot, to} ->
              send(to, {:events, Enum.reverse(events)})
          end
        end

        loop.(loop, [])
      end)

    session = :trace.session_create(:parallel_installation, collector, [])

    {elapsed, _} =
      :timer.tc(fn ->
        if concurrency == 1 do
          Enum.each(mfas, fn mfa -> 1 = :trace.function(session, mfa, true, [:local]) end)
        else
          mfas
          |> Enum.chunk_every(div(length(mfas) + concurrency - 1, concurrency))
          |> Task.async_stream(
            fn group ->
              Enum.each(group, fn mfa -> 1 = :trace.function(session, mfa, true, [:local]) end)
            end,
            max_concurrency: concurrency,
            ordered: false,
            timeout: 30_000
          )
          |> Enum.each(fn {:ok, :ok} -> :ok end)
        end
      end)

    for mfa <- mfas, do: {:traced, :local} = :trace.info(session, mfa, :traced)

    for module <- modules,
        arity <- [0, 1],
        do: {:traced, false} = :trace.info(session, {module, :module_info, arity}, :traced)

    1 = :trace.process(session, self(), true, [:call])
    selected = Enum.take(mfas, 10)
    for {module, function, _} <- selected, do: :input = apply(module, function, [:input])
    ref = :trace.delivered(session, self())

    receive do
      {:trace_delivered, _, ^ref} -> :ok
    after
      5_000 -> raise "delivery timeout"
    end

    :trace.process(session, self(), false, [:call])
    send(collector, {:snapshot, self()})
    expected = for {module, function, _} <- selected, do: {self(), module, function, [:input]}

    receive do
      {:events, ^expected} -> :ok
    after
      5_000 -> raise "events mismatch"
    end

    :trace.session_destroy(session)
    [legacy: :default] = :trace.session_info(:all)

    row = %{
      trial: trial,
      concurrency: concurrency,
      installation_us: elapsed,
      patterns: length(mfas),
      observed_calls: 10,
      cleanup: true
    }

    IO.puts(JSON.encode!(row))
    row
  end

File.write!(output, JSON.encode!(rows) <> "\n")
