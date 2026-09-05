Code.require_file("semantic-fixtures.exs", __DIR__)
Code.require_file("target-plan.exs", __DIR__)

ExUnit.start(
  case System.get_env("BYLAW_PRODUCER_SEED") do
    nil -> []
    seed -> [seed: String.to_integer(seed)]
  end
)

defmodule ProducerFixture do
  def call(:raise), do: raise("fixture error")
  def call(:throw), do: throw(:fixture_throw)
  def call(:exit), do: exit(:fixture_exit)
  def call(value), do: value

  def second(_ignored, value), do: value

  def block(parent) do
    send(parent, {:entered, self()})

    receive do
      :resume -> :resumed
    end
  end
end

defmodule ProducerTransportAcceptance do
  use ExUnit.Case, async: false

  defp start(resource \\ ProducerNative.new()) do
    session = :trace.session_create(:producer_prototype, {ProducerNative, resource}, [])
    :trace.function(session, {ProducerFixture, :call, 1}, [{:_, [], [{:return_trace}]}], [:local])
    ProducerNative.watch_code_changes(session)
    :trace.process(session, :all, true, [:call])
    {session, resource}
  end

  defp stop({session, resource}) do
    :trace.session_destroy(session)
    ProducerNative.counts(resource)
  end

  defp burst do
    parent = self()

    for _ <- 1..8 do
      spawn(fn ->
        for _ <- 1..8192, do: ProducerFixture.call(:binary.copy(<<1>>, 4096))
        send(parent, :done)
      end)
    end

    for _ <- 1..8,
        do:
          (receive do
             :done -> :ok
           after
             10_000 -> flunk("producer timeout")
           end)
  end

  defp outcome(value) do
    try do
      {:returned, ProducerFixture.call(value)}
    catch
      kind, reason ->
        {kind, reason, __STACKTRACE__}
    end
  end

  test "concurrent bursts preserve exact call and return totals without a trace mailbox" do
    session = start()
    burst()
    assert stop(session) == {65536, 65536}
  end

  test "observing leaves return raise throw exit and stack behavior unchanged" do
    inputs = [:normal, :raise, :throw, :exit]

    [baseline, observed] =
      Enum.map([false, true], fn enabled ->
        parent = self()

        {pid, ref} =
          spawn_monitor(fn ->
            observer = if enabled, do: start()
            outcomes = Enum.map(inputs, &outcome/1)
            if enabled, do: assert(stop(observer) == {4, 1})
            send(parent, {:outcomes, self(), outcomes})
          end)

        outcomes =
          receive do
            {:outcomes, ^pid, outcomes} -> outcomes
            {:DOWN, ^ref, :process, ^pid, reason} -> flunk(inspect(reason))
          after
            10_000 -> flunk("outcome timeout")
          end

        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
        outcomes
      end)

    assert observed == baseline
  end

  test "independent sessions count the same calls and stop independently" do
    first = start()
    second = start()
    ProducerFixture.call(:first)
    assert stop(first) == {1, 1}
    ProducerFixture.call(:second)
    assert stop(second) == {2, 2}
  end

  test "repeated sessions release tracepoints and keep counters fixed in size" do
    for _ <- 1..3 do
      {session, resource} = observer = start()
      bytes = ProducerNative.bytes(resource)
      burst()
      assert stop(observer) == {65536, 65536}
      assert ProducerNative.bytes(resource) == bytes
      assert bytes <= 128

      assert_raise ArgumentError, fn ->
        :trace.info(session, {ProducerFixture, :call, 1}, :traced)
      end
    end
  end

  test "counter exhaustion saturates totals and reports incomplete" do
    resource = ProducerNative.new(3)
    session = start(resource)
    for _ <- 1..3, do: ProducerFixture.call(:ok)
    assert ProducerNative.status(resource) == :complete, inspect(ProducerNative.reasons(resource))
    ProducerFixture.call(:ok)
    assert stop(session) == {3, 3}
    assert ProducerNative.status(resource) == :incomplete
  end

  test "concurrent exhaustion cannot wrap counters or clear incomplete status" do
    resource = ProducerNative.new(1024)
    session = start(resource)
    burst()
    assert stop(session) == {1024, 1024}
    assert ProducerNative.status(resource) == :incomplete
  end

  test "native counters retain overlapping VM classification outcomes" do
    resource = ProducerNative.new()
    {session, _} = observer = start(resource)

    flags =
      {{:is_integer, :"$1"}, {:andalso, {:is_integer, :"$1"}, {:>, :"$1", 0}},
       {:is_binary, :"$1"}, {:==, :"$1", {:self}}}

    specification = [{[:"$1"], [], [{:message, {flags}}, {:return_trace}]}]
    assert :trace.function(session, {ProducerFixture, :call, 1}, specification, [:local]) == 1
    for value <- [-1, 1, <<1>>, self(), :other], do: ProducerFixture.call(value)
    assert stop(observer) == {5, 5}
    assert ProducerNative.hits(resource) == [2, 1, 1, 1, 0, 0, 0, 0]
    assert ProducerNative.status(resource) == :complete, inspect(ProducerNative.reasons(resource))
  end

  test "unsupported classification result marks transport incomplete" do
    {session, resource} = observer = start()

    :trace.function(
      session,
      {ProducerFixture, :call, 1},
      [{:_, [], [{:message, :unsupported}]}],
      [:local]
    )

    ProducerFixture.call(:ok)
    assert stop(observer) == {1, 0}
    assert ProducerNative.status(resource) == :incomplete
  end

  test "stopping during an active call freezes the snapshot and isolates a later session" do
    {session, resource} = first = start()

    :trace.function(session, {ProducerFixture, :block, 1}, [{:_, [], [{:return_trace}]}], [:local])

    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        assert ProducerFixture.block(parent) == :resumed
      end)

    assert_receive {:entered, ^pid}
    assert stop(first) == {1, 0}
    second = start()
    send(pid, :resume)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert ProducerNative.counts(resource) == {1, 0}
    assert stop(second) == {0, 0}
  end

  test "destroyed sessions release native resources after their owners exit" do
    for _ <- 1..3 do
      parent = self()

      {pid, ref} =
        spawn_monitor(fn ->
          resource = ProducerNative.new(18_446_744_073_709_551_615, parent)
          observer = start(resource)
          send(parent, {:live, self()})

          receive do
            :stop -> :ok
          end

          stop(observer)
        end)

      assert_receive {:live, ^pid}
      refute_receive :producer_resource_released, 10
      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      receive do
        :producer_resource_released -> :ok
      after
        1_000 ->
          for tracee <- Process.list(), do: :erlang.garbage_collect(tracee)
          assert_receive :producer_resource_released, 1_000
          IO.puts("Resource release required collection of traced-process heaps")
      end
    end
  end

  test "module reload cannot silently produce complete partial observations" do
    Code.compile_string(
      "defmodule ProducerReloadFixture do def call(value), do: {:before, value} end"
    )

    resource = ProducerNative.new()
    session = :trace.session_create(:producer_reload, {ProducerNative, resource}, [])

    :trace.function(session, {ProducerReloadFixture, :call, 1}, [{:_, [], [{:return_trace}]}], [
      :local
    ])

    ProducerNative.watch_code_changes(session)
    :trace.process(session, :all, true, [:call])

    try do
      assert apply(ProducerReloadFixture, :call, [:value]) == {:before, :value}

      Code.compile_string(
        "defmodule ProducerReloadFixture do def call(value), do: {:after, value} end"
      )

      assert apply(ProducerReloadFixture, :call, [:value]) == {:after, :value}
    after
      :trace.session_destroy(session)
      :code.purge(ProducerReloadFixture)
      :code.delete(ProducerReloadFixture)
    end

    assert ProducerNative.counts(resource) == {2, 2} or
             ProducerNative.status(resource) == :incomplete
  end

  test "identical bytecode reload invalidates observation even when module hash is unchanged" do
    [{module, binary}] =
      Code.compile_string("defmodule ProducerIdenticalFixture do def call(value), do: value end")

    md5 = module.module_info(:md5)
    {session, resource} = observer = start()
    :trace.function(session, {module, :call, 1}, [{:_, [], [{:return_trace}]}], [:local])

    try do
      assert apply(module, :call, [:before]) == :before
      assert :ok = :code.atomic_load([{module, ~c"producer_identical", binary}])
      assert module.module_info(:md5) == md5
      assert apply(module, :call, [:after]) == :after
      assert ProducerNative.status(resource) == :incomplete
    after
      stop(observer)
      :code.purge(module)
      :code.delete(module)
    end
  end

  test "code deletion invalidates observation without counting loader calls" do
    [{module, _}] =
      Code.compile_string("defmodule ProducerDeletedFixture do def call(value), do: value end")

    {_session, resource} = observer = start()

    try do
      assert :code.delete(module)
      assert ProducerNative.status(resource) == :incomplete
      assert ProducerNative.counts(resource) == {0, 0}
    after
      stop(observer)
      :code.purge(module)
    end
  end

  test "bounded native integer-list matching preserves exact input and return hits" do
    inputs = [
      [],
      [1],
      [1, -1, Integer.pow(2, 100)],
      [1, 2, 3, 4],
      [1, 2.0],
      [1 | :tail],
      <<1>>,
      :not_a_list
    ]

    resource = ProducerNative.integer_list(4)
    observer = start(resource)
    for value <- inputs, do: assert(ProducerFixture.call(value) == value)
    assert stop(observer) == {8, 8}
    assert ProducerNative.hits(resource) == [4, 4, 0, 0, 0, 0, 0, 0]
    assert ProducerNative.status(resource) == :complete, inspect(ProducerNative.reasons(resource))
  end

  test "native list traversal exhaustion reports incomplete without claiming a hit" do
    resource = ProducerNative.integer_list(4)
    observer = start(resource)
    value = List.duplicate(1, 5)
    assert ProducerFixture.call(value) == value
    assert stop(observer) == {1, 1}
    assert ProducerNative.hits(resource) == [0, 0, 0, 0, 0, 0, 0, 0]
    assert ProducerNative.status(resource) == :incomplete
  end

  test "bounded native list classification agrees with the existing matcher across list shapes" do
    Code.require_file(Path.expand("../../lib/bylaw/contract/type_matcher.ex", __DIR__))
    type = {:type, 0, :list, [{:type, 0, :integer, []}]}

    for length <- 0..32 do
      integers = List.duplicate(Integer.pow(2, 100), length)

      for value <- [integers, integers ++ [0.5], integers ++ [:bad], integers ++ [1 | :tail]] do
        expected = apply(Bylaw.Contract.TypeMatcher, :match, [value, type])
        assert expected in [:match, :no_match]
        hit = if expected == :match, do: 1, else: 0
        resource = ProducerNative.integer_list(64)
        observer = start(resource)
        assert ProducerFixture.call(value) == value
        assert stop(observer) == {1, 1}
        assert ProducerNative.hits(resource) == [hit, hit, 0, 0, 0, 0, 0, 0]

        assert ProducerNative.status(resource) == :complete,
               inspect(ProducerNative.reasons(resource))
      end
    end
  end

  test "native observation preserves local recursion and captured local calls" do
    assert ProducerSemanticFixture.count(5) == :done
    assert ProducerSemanticFixture.captured_count(3) == :done
    {session, resource} = observer = start()

    1 =
      :trace.function(
        session,
        {ProducerSemanticFixture, :count, 1},
        [{:_, [], [{:return_trace}]}],
        [:local]
      )

    assert ProducerSemanticFixture.count(5) == :done
    assert ProducerNative.counts(resource) == {6, 6}
    assert ProducerSemanticFixture.captured_count(3) == :done
    assert stop(observer) == {10, 10}
    assert ProducerNative.status(resource) == :complete, inspect(ProducerNative.reasons(resource))
  end

  test "native observation preserves default wrappers and protocol dispatch" do
    value = %ProducerSemanticPayload{value: 17}
    implementation = ProducerSemanticProtocol.impl_for(value)
    assert ProducerSemanticFixture.deliver(:value) == {:default, :value}
    assert ProducerSemanticProtocol.tag(value) == {:tagged, 17}
    {session, resource} = observer = start()

    for mfa <- [
          {ProducerSemanticFixture, :deliver, 1},
          {ProducerSemanticFixture, :deliver, 2},
          {implementation, :tag, 1}
        ] do
      1 = :trace.function(session, mfa, [{:_, [], [{:return_trace}]}], [:local])
    end

    assert ProducerSemanticFixture.deliver(:value) == {:default, :value}
    assert ProducerNative.counts(resource) == {2, 2}
    assert ProducerSemanticFixture.deliver(:value, :explicit) == {:explicit, :value}
    assert ProducerNative.counts(resource) == {3, 3}
    assert ProducerSemanticProtocol.tag(value) == {:tagged, 17}
    assert stop(observer) == {4, 4}
    assert ProducerNative.status(resource) == :complete, inspect(ProducerNative.reasons(resource))
  end

  test "unmatched clauses preserve complete exception stack traces" do
    [baseline, observed] =
      for enabled <- [false, true] do
        parent = self()

        {pid, ref} =
          spawn_monitor(fn ->
            observer =
              if enabled do
                {session, _} = observer = start()

                1 =
                  :trace.function(
                    session,
                    {ProducerSemanticFixture, :strict, 1},
                    [{:_, [], [{:return_trace}]}],
                    [:local]
                  )

                observer
              end

            result =
              try do
                ProducerSemanticFixture.strict(:rejected)
              catch
                kind, reason -> {kind, reason, __STACKTRACE__}
              end

            counts = if enabled, do: stop(observer)
            send(parent, {:semantic_result, self(), result, counts})
          end)

        receive do
          {:semantic_result, ^pid, result, counts} ->
            if enabled, do: assert(counts == {1, 0})
            assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
            result

          {:DOWN, ^ref, :process, ^pid, reason} ->
            flunk(inspect(reason))
        after
          10_000 -> flunk("semantic timeout")
        end
      end

    assert observed == baseline
    assert {:error, :function_clause, _} = observed
  end

  test "VM flags retain overlapping clause head guard and selection outcomes" do
    assert ProducerSemanticFixture.choose(1) == :positive
    assert ProducerSemanticFixture.choose(0) == :integer
    assert_raise FunctionClauseError, fn -> ProducerSemanticFixture.choose(:not_integer) end
    {session, resource} = observer = start()
    integer = {:is_integer, :"$1"}
    positive = {:andalso, integer, {:>, :"$1", 0}}
    second_selected = {:andalso, integer, {:not, positive}}

    flags =
      {true, positive, positive, {:not, positive}, true, integer, second_selected,
       {:not, integer}}

    1 =
      :trace.function(
        session,
        {ProducerSemanticFixture, :choose, 1},
        [{[:"$1"], [], [{:message, {flags}}, {:return_trace}]}],
        [:local]
      )

    assert ProducerSemanticFixture.choose(1) == :positive
    assert ProducerSemanticFixture.choose(-1) == :integer
    assert ProducerSemanticFixture.choose(0) == :integer
    assert_raise FunctionClauseError, fn -> ProducerSemanticFixture.choose(:not_integer) end
    assert stop(observer) == {4, 3}
    assert ProducerNative.hits(resource) == [4, 1, 1, 3, 4, 3, 2, 1]
    assert ProducerNative.status(resource) == :complete, inspect(ProducerNative.reasons(resource))
  end

  test "incomplete observation retains all counter and classification failure reasons" do
    resource = ProducerNative.new(1)
    {session, _} = observer = start(resource)

    :trace.function(
      session,
      {ProducerFixture, :call, 1},
      [{:_, [], [{:message, :unsupported}]}],
      [:local]
    )

    ProducerFixture.call(:ok)
    ProducerFixture.call(:ok)
    assert stop(observer) == {1, 0}
    assert ProducerNative.reasons(resource) == [:counter_limit, :invalid_classification]
  end

  test "clause outcomes remain exact across burst paced concurrent and large-integer callers" do
    for bits <- [16, 4096], {producers, pacing} <- [{1, :burst}, {8, :burst}, {8, :paced}] do
      big = Integer.pow(2, bits)
      inputs = [big, -big, 0, :not_integer]
      expected = [:positive, :integer, :integer, :function_clause]
      assert Enum.map(inputs, &choose_outcome/1) == expected
      {session, resource} = observer = start()
      integer = {:is_integer, :"$1"}
      positive = {:andalso, integer, {:>, :"$1", 0}}

      flags =
        {true, positive, positive, {:not, positive}, true, integer,
         {:andalso, integer, {:not, positive}}, {:not, integer}}

      1 =
        :trace.function(
          session,
          {ProducerSemanticFixture, :choose, 1},
          [{[:"$1"], [], [{:message, {flags}}, {:return_trace}]}],
          [:local]
        )

      parent = self()

      children =
        for _ <- 1..producers do
          spawn_monitor(fn ->
            for index <- 1..div(2048, producers) do
              assert Enum.map(inputs, &choose_outcome/1) == expected
              if pacing == :paced and rem(index, 2) == 0, do: Process.sleep(5)
            end

            send(parent, {:clause_done, self()})
          end)
        end

      for {pid, ref} <- children do
        assert_receive {:clause_done, ^pid}, 10_000
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      end

      assert stop(observer) == {8192, 6144}
      assert ProducerNative.hits(resource) == [8192, 2048, 2048, 6144, 8192, 6144, 4096, 2048]

      assert ProducerNative.status(resource) == :complete,
             inspect(ProducerNative.reasons(resource))
    end
  end

  defp choose_outcome(value) do
    ProducerSemanticFixture.choose(value)
  catch
    :error, :function_clause -> :function_clause
  end

  test "native target rules distinguish functions arguments and overlapping slots" do
    entries = [
      {:call,
       %{
         id: :a,
         module: ProducerFixture,
         function: :call,
         arity: 1,
         argument: 1,
         supported?: true,
         match_type: {:type, 0, :integer, []}
       }},
      {:call,
       %{
         id: :b,
         module: ProducerFixture,
         function: :second,
         arity: 2,
         argument: 2,
         supported?: true,
         match_type: {:type, 0, :list, [{:type, 0, :integer, []}]}
       }},
      {:call,
       %{
         id: :c,
         module: ProducerFixture,
         function: :second,
         arity: 2,
         argument: 2,
         supported?: true,
         match_type: {:bylaw_contract, :list_length, :multiple, {:type, 0, :integer, []}}
       }},
      {:return,
       %{
         id: :d,
         module: ProducerFixture,
         function: :second,
         arity: 2,
         supported?: true,
         match_type: {:type, 0, :list, [{:type, 0, :integer, []}]}
       }}
    ]

    {:ok, plan} = ProducerTargetPlan.compile(entries)
    resource = ProducerNative.plan(plan.rules, 32)
    session = :trace.session_create(:producer_target_plan, {ProducerNative, resource}, [])

    try do
      for mfa <- plan.mfas do
        assert :trace.function(session, mfa, [{:_, [], [{:return_trace}]}], [:local]) == 1
      end

      ProducerNative.watch_code_changes(session)
      :trace.process(session, self(), true, [:call])
      assert ProducerFixture.call(4) == 4
      assert ProducerFixture.call(:other) == :other

      for value <- [[], [1], [1, 2], [1 | :tail], [false]] do
        assert ProducerFixture.second(:ignored, value) == value
      end
    after
      :trace.session_destroy(session)
    end

    assert ProducerNative.counts(resource) == {7, 7}
    assert ProducerNative.hits(resource) == [1, 3, 1, 3, 0, 0, 0, 0]
    assert ProducerNative.status(resource) == :complete
    assert ProducerNative.bytes(resource) <= 8192
  end

  test "native target rules reject invalid plans and bound shared traversal" do
    rule = {ProducerFixture, :call, 1, :call, 1, :integer_list}
    assert_raise ArgumentError, fn -> ProducerNative.plan([], 4) end
    assert_raise ArgumentError, fn -> ProducerNative.plan(List.duplicate(rule, 9), 4) end
    assert_raise ArgumentError, fn -> ProducerNative.plan([put_elem(rule, 4, 2)], 4) end
    assert_raise ArgumentError, fn -> ProducerNative.plan([put_elem(rule, 5, :unknown)], 4) end
    resource = ProducerNative.plan([rule, rule], 3)
    session = start(resource)
    assert ProducerFixture.call([1, 2]) == [1, 2]
    assert stop(session) == {1, 1}
    assert ProducerNative.hits(resource) == [1, 0, 0, 0, 0, 0, 0, 0]
    assert ProducerNative.reasons(resource) == [:traversal_budget]
  end

  test "explicit counter allocations support larger bounded clause plans" do
    for invalid <- [0, 7, 65, :invalid] do
      assert_raise ArgumentError, fn -> ProducerNative.new_slots(invalid) end
    end

    for size <- [8, 12, 64] do
      resource = ProducerNative.new_slots(size)

      assert ProducerNative.bytes(resource) ==
               ProducerNative.bytes(ProducerNative.new()) + (size - 8) * 8

      flags = for slot <- 0..(size - 1), do: rem(slot, 3) == 0
      expected = Enum.map(flags, &if(&1, do: 8192, else: 0))
      session = :trace.session_create(:producer_sized_counters, {ProducerNative, resource}, [])

      try do
        tuple = List.to_tuple(flags)

        assert :trace.function(
                 session,
                 {ProducerFixture, :call, 1},
                 [{:_, [], [{:message, {tuple}}, {:return_trace}]}],
                 [:local]
               ) == 1

        ProducerNative.watch_code_changes(session)
        :trace.process(session, :all, true, [:call])
        parent = self()

        for _ <- 1..8 do
          spawn(fn ->
            for _ <- 1..1024, do: ProducerFixture.call(:ok)
            send(parent, :counter_done)
          end)
        end

        for _ <- 1..8 do
          assert_receive :counter_done, 5000
        end
      after
        :trace.session_destroy(session)
      end

      assert ProducerNative.hits(resource) == expected
      assert ProducerNative.counts(resource) == {8192, 8192}

      assert ProducerNative.status(resource) == :complete,
             inspect(ProducerNative.reasons(resource))
    end
  end

  test "native tuple descriptors classify nested returns and arbitrary size integer signs" do
    rules = [
      {ProducerFixture, :call, 1, :return, 0,
       {:tuple, [{:literal_atom, :tag}, {:tuple, [:non_neg_integer, :binary]}]}},
      {ProducerFixture, :call, 1, :call, 1, :neg_integer},
      {ProducerFixture, :call, 1, :return, 0, :pos_integer}
    ]

    resource = ProducerNative.plan(rules, 32)
    observer = start(resource)
    big = Integer.pow(2, 4096)

    for value <- [
          {:tag, {0, ""}},
          {:tag, {big, "ok"}},
          {:tag, {-1, "bad"}},
          {:tag, {1.0, "bad"}},
          {:wrong, {1, "bad"}},
          {:tag, {1, :bad}},
          {:tag},
          {1, 2, 3},
          -big,
          big,
          0,
          1.0
        ] do
      assert ProducerFixture.call(value) == value
    end

    assert stop(observer) == {12, 12}
    assert ProducerNative.hits(resource) == [2, 1, 1, 0, 0, 0, 0, 0]
    assert ProducerNative.status(resource) == :complete
    assert ProducerNative.bytes(resource) <= 8192

    full =
      List.duplicate(
        {ProducerFixture, :call, 1, :return, 0, {:tuple, List.duplicate(:integer, 7)}},
        8
      )

    full_resource = ProducerNative.plan(full, 128)
    full_observer = start(full_resource)
    tuple = {1, 2, 3, 4, 5, 6, 7}
    assert ProducerFixture.call(tuple) == tuple
    assert stop(full_observer) == {1, 1}
    assert ProducerNative.hits(full_resource) == List.duplicate(1, 8)
    assert ProducerNative.status(full_resource) == :complete
    too_many = Enum.map(full, &put_elem(&1, 5, {:tuple, List.duplicate(:integer, 8)}))
    assert_raise ArgumentError, fn -> ProducerNative.plan(too_many, 128) end
    oversized = {:tuple, List.duplicate(:integer, 9)}

    assert_raise ArgumentError, fn ->
      ProducerNative.plan([put_elem(hd(rules), 5, oversized)], 32)
    end

    deep = Enum.reduce(1..12, :integer, fn _, child -> {:tuple, [child]} end)
    assert_raise ArgumentError, fn -> ProducerNative.plan([put_elem(hd(rules), 5, deep)], 32) end
  end

  test "combined observations preserve target and clause slots without double counting events" do
    rules = [
      {ProducerFixture, :call, 1, :call, 1, :integer},
      {ProducerFixture, :call, 1, :return, 0, :integer}
    ]

    resource = ProducerNative.plan(rules, 32, 4)
    {session, _} = observer = start(resource)
    integer = {:is_integer, :"$1"}
    flags = {true, integer, integer, {:not, integer}}

    assert :trace.function(
             session,
             {ProducerFixture, :call, 1},
             [{[:"$1"], [], [{:message, {flags}}, {:return_trace}]}],
             [:local]
           ) == 1

    for value <- [1, 2, :other], do: assert(ProducerFixture.call(value) == value)
    assert stop(observer) == {3, 3}
    assert ProducerNative.hits(resource) == [2, 2, 3, 2, 2, 1, 0, 0]
    assert ProducerNative.status(resource) == :complete
  end

  test "combined observations reject missing clause flags and excessive total capacity" do
    rules = [{ProducerFixture, :call, 1, :call, 1, :integer}]
    assert_raise ArgumentError, fn -> ProducerNative.plan(rules, 32, 64) end
    assert_raise ArgumentError, fn -> ProducerNative.plan(rules, 32, :invalid) end
    resource = ProducerNative.plan(rules, 32, 4)
    observer = start(resource)
    ProducerFixture.call(1)
    assert stop(observer) == {1, 1}
    assert ProducerNative.hits(resource) == [1, 0, 0, 0, 0, 0, 0, 0]
    assert ProducerNative.reasons(resource) == [:invalid_classification]
  end
end
