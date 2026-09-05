defmodule Bylaw.Contract.GenericBehaviorAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias ContractCompatibility.{Actions, Label, Payload}

  test "default observation preserves normal returns raises throws and exits from child callers" do
    expected = [
      :ok,
      {:raised, ArgumentError, "fixture raise"},
      {:throw, :fixture_throw},
      {:exit, :fixture_exit}
    ]

    assert child_actions() == expected
    coverage = capture([Actions], fn -> assert child_actions() == expected end)
    assert coverage.calls[{Actions, :perform, 2}] == 4
    assert coverage.return_events[{Actions, :perform, 2}] == 1
    assert selected_counts(coverage, Actions, :perform, 2) == [1, 1, 1, 1]
    returns = Enum.filter(coverage.return_alternatives, &(&1.function == :perform))
    assert Enum.map(returns, & &1.label) |> Enum.sort() == [":ok", ":unused"]

    assert Map.new(returns, &{&1.label, Map.get(coverage.hits, &1.id, 0)}) == %{
             ":ok" => 1,
             ":unused" => 0
           }
  end

  test "protocol struct dispatch retains independently expected targets and default arities" do
    implementation = Label.impl_for(%Payload{})
    coverage = capture([implementation, Actions], &child_labels/0)
    assert selected_counts(coverage, implementation, :label, 1) == [1, 1]
    assert Enum.count(coverage.clauses, &(&1.module == implementation)) == 2

    [struct_input] =
      Enum.filter(
        coverage.input_classes,
        &(&1.module == Actions and &1.function == :label and &1.argument == 1)
      )

    assert struct_input.supported?
    assert struct_input.label == "ContractCompatibility.Payload.t()"
    assert Map.fetch!(coverage.hits, struct_input.id) == 2
    assert selected_counts(coverage, Actions, :label, 2) == [2, 0]
    assert selected_counts(coverage, Actions, :label, 1) == []
    assert coverage.arity_calls[{Actions, :label, 1}] == 1
    assert coverage.arity_calls[{Actions, :label, 2}] == 2
    assert coverage.arity_calls[{implementation, :label, 1}] == 2
    assert coverage.return_events[{Actions, :label, 2}] == 2

    targets =
      Enum.filter(
        coverage.input_classes,
        &(&1.module == Actions and &1.function == :label and &1.argument == 2)
      )

    assert Enum.map(targets, & &1.label) |> Enum.sort() == [":normal", ":quiet"]
    assert Enum.all?(targets, & &1.supported?)

    assert Map.new(targets, &{&1.label, Map.get(coverage.hits, &1.id, 0)}) == %{
             ":normal" => 2,
             ":quiet" => 0
           }
  end

  test "repeated observations respect explicit module scope and preserve original code" do
    implementation = Label.impl_for(%Payload{})
    original = Map.new([Actions, implementation], &{&1, {&1.module_info(:md5), :code.which(&1)}})

    for _ <- 1..3 do
      coverage = capture([Actions], &child_labels/0)
      assert Enum.all?(coverage.clauses, &(&1.module == Actions))
      refute Map.has_key?(coverage.arity_calls, {implementation, :label, 1})
      assert coverage.arity_calls[{Actions, :label, 2}] == 2

      for {module, object} <- original,
          do: assert({module.module_info(:md5), :code.which(module)} == object)

      assert Label.label(%Payload{flag: :present}) == :present
    end
  end

  defp capture(modules, action) do
    {:ok, observer} = Contract.start(modules)

    try do
      action.()
      coverage = Contract.stop(observer)
      refute Map.has_key?(coverage, :incomplete)
      assert Enum.all?(coverage.structural_modules, &(&1.status == :supported))
      coverage
    after
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  defp selected_counts(coverage, module, function, arity) do
    coverage.clauses
    |> Enum.filter(&(&1.module == module and &1.function == function and &1.arity == arity))
    |> Enum.sort_by(& &1.position)
    |> Enum.map(&Map.fetch!(coverage.clause_outcomes, &1.id).selected)
  end

  defp child_actions do
    parent = self()

    {child, monitor} =
      spawn_monitor(fn ->
        results =
          Enum.map([:return, :raise, :throw, :exit], fn action ->
            try do
              Actions.perform(action, parent)
            rescue
              error -> {:raised, error.__struct__, Exception.message(error)}
            catch
              kind, value -> {kind, value}
            end
          end)

        send(parent, {self(), :results, results})
      end)

    assert_receive {^child, :results, results}
    for action <- [:return, :raise, :throw, :exit], do: assert_receive({^child, :body, ^action})
    assert_receive {:DOWN, ^monitor, :process, ^child, :normal}
    refute_receive {^child, :body, _}
    results
  end

  defp child_labels do
    parent = self()

    {child, monitor} =
      spawn_monitor(fn ->
        send(
          parent,
          {self(), Actions.label(%Payload{flag: :present}),
           Actions.label(%Payload{flag: :empty}, :normal)}
        )
      end)

    assert_receive {^child, :present, :empty}
    assert_receive {:DOWN, ^monitor, :process, ^child, :normal}
  end
end
