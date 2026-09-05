ExUnit.start()

defmodule ProducerTargetPlanTest do
  use ExUnit.Case

  defp target(id, function, argument, type) do
    %{
      id: id,
      module: ProducerFixture,
      function: function,
      arity: 2,
      argument: argument,
      match_type: type,
      supported?: true
    }
  end

  test "target plans preserve IDs argument positions and independent MFAs" do
    entries = [
      {:return, target(:result, :first, nil, {:atom, 0, :ok})},
      {:call,
       target(
         :input,
         :first,
         2,
         {:bylaw_contract, :list_length, :multiple, {:type, 0, :integer, []}}
       )},
      {:call, target(:other, :second, 1, {:type, 0, :binary, []})}
    ]

    assert {:ok, plan} = ProducerTargetPlan.compile(entries)
    assert {:ok, ^plan} = ProducerTargetPlan.compile(Enum.reverse(entries))
    assert plan.slots == %{input: 0, other: 1, result: 2}

    assert plan.rules == [
             {ProducerFixture, :first, 2, :call, 2, :multiple_integer_list},
             {ProducerFixture, :second, 2, :call, 1, :binary},
             {ProducerFixture, :first, 2, :return, 0, {:literal_atom, :ok}}
           ]

    assert plan.mfas == [{ProducerFixture, :first, 2}, {ProducerFixture, :second, 2}]
  end

  test "unsupported target types reject the entire plan explicitly" do
    supported = {:call, target(:good, :first, 1, {:type, 0, :integer, []})}

    unsupported =
      {:call, target(:recursive, :second, 1, {:bylaw_contract, :type_graph, :root, %{}})}

    assert ProducerTargetPlan.compile([supported, unsupported]) ==
             {:error, {:unsupported_target, :recursive}}

    assert ProducerTargetPlan.compile([
             {:call, target(:wrong_argument, :first, 3, {:type, 0, :integer, []})}
           ]) ==
             {:error, {:invalid_target, :wrong_argument}}
  end

  test "target plans reject capacity overflow and duplicate IDs" do
    target = {:call, target(:same, :first, 1, {:type, 0, :integer, []})}
    assert ProducerTargetPlan.compile([target, target]) == {:error, :duplicate_target_ids}
    assert ProducerTargetPlan.compile(List.duplicate(target, 9)) == {:error, :target_capacity}
    assert ProducerTargetPlan.compile([]) == {:error, :empty_plan}
  end

  test "persisted typespec metadata maps every list input partition and return alternative" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "producer-target-plan-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      :code.purge(ProducerTargetPlanFixture)
      :code.delete(ProducerTargetPlanFixture)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end)

    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule ProducerTargetPlanFixture do
      @spec echo(list(integer())) :: list(integer()) | :unused
      def echo(value), do: value
    end
    """)

    {:ok, _, _} =
      Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)

    Code.prepend_path(directory)
    {:module, ProducerTargetPlanFixture} = Code.ensure_loaded(ProducerTargetPlanFixture)
    metadata = Bylaw.Contract.Specs.load([ProducerTargetPlanFixture])
    assert metadata.warnings == []
    assert metadata.boundaries == []
    assert length(metadata.input_classes) == 3
    assert length(metadata.return_alternatives) == 2

    entries =
      Enum.map(metadata.input_classes, &{:call, &1}) ++
        Enum.map(metadata.return_alternatives, &{:return, &1})

    assert {:ok, plan} = ProducerTargetPlan.compile(entries)

    assert Map.keys(plan.slots) |> Enum.sort() ==
             Enum.map(entries, fn {_, target} -> target.id end) |> Enum.sort()

    assert Enum.map(plan.rules, &elem(&1, 5)) |> Enum.sort() ==
             Enum.sort([
               :empty_integer_list,
               :singleton_integer_list,
               :multiple_integer_list,
               :integer_list,
               {:literal_atom, :unused}
             ])
  end

  test "target plans resolve bounded tuple aliases and integer sign classes" do
    graph =
      {:bylaw_contract, :type_graph,
       {:type, 0, :tuple, [{:atom, 0, :insert}, {:bylaw_contract, :type_ref, 0}]},
       %{0 => {{:type, 0, :binary, []}, true}}}

    entries = [
      {:return, target(:a, :first, nil, graph)},
      {:return,
       target(
         :b,
         :first,
         nil,
         {:type, 0, :tuple, [{:atom, 0, :retain}, {:type, 0, :non_neg_integer, []}]}
       )},
      {:call, target(:c, :first, 1, {:type, 0, :neg_integer, []})}
    ]

    assert {:ok, plan} = ProducerTargetPlan.compile(entries)

    assert Enum.map(plan.rules, &elem(&1, 5)) == [
             {:tuple, [{:literal_atom, :insert}, :binary]},
             {:tuple, [{:literal_atom, :retain}, :non_neg_integer]},
             :neg_integer
           ]
  end

  test "target plans reject recursive and oversized tuple metadata" do
    recursive =
      {:bylaw_contract, :type_graph, {:bylaw_contract, :type_ref, 0},
       %{0 => {{:type, 0, :tuple, [{:bylaw_contract, :type_ref, 0}]}, true}}}

    wide = {:type, 0, :tuple, List.duplicate({:type, 0, :integer, []}, 9)}

    deep =
      Enum.reduce(1..12, {:type, 0, :integer, []}, fn _, type -> {:type, 0, :tuple, [type]} end)

    for type <- [recursive, wide, deep] do
      assert ProducerTargetPlan.compile([{:return, target(:limited, :first, nil, type)}]) ==
               {:error, {:unsupported_target, :limited}}
    end
  end

  test "target plans share the native descriptor node capacity across rules" do
    entries =
      for index <- 1..8 do
        type = {:type, 0, :tuple, List.duplicate({:type, 0, :integer, []}, 7)}
        {:return, target(index, :first, nil, type)}
      end

    assert {:ok, plan} = ProducerTargetPlan.compile(entries)
    assert length(plan.rules) == 8

    oversized =
      Enum.map(entries, fn {event, target} ->
        {event,
         %{target | match_type: {:type, 0, :tuple, List.duplicate({:type, 0, :integer, []}, 8)}}}
      end)

    assert ProducerTargetPlan.compile(oversized) == {:error, :metadata_capacity}
  end
end
