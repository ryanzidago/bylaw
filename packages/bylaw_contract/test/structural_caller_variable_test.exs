defmodule Bylaw.Contract.StructuralCallerVariableTest do
  use ExUnit.Case

  alias Bylaw.Contract.StructuralCoverage

  test "injected caller identity does not capture an existing source variable" do
    source_variable = {:var, 0, :_BylawContractCaller0}
    source_self = {:call, 0, {:remote, 0, {:atom, 0, :erlang}, {:atom, 0, :self}}, []}
    guard = {:op, 0, :"=:=", source_variable, source_self}

    clauses = [
      %{
        id: {__MODULE__, :who, 1, 1, 1},
        clause: {:clause, 0, [source_variable], [[guard]], [{:atom, 0, :caller}]}
      },
      %{
        id: {__MODULE__, :who, 1, 2, 2},
        clause: {:clause, 0, [{:var, 0, :_}], [], [{:atom, 0, :other}]}
      }
    ]

    classifiers = [
      %{
        classifier_function: :who,
        mfa_classifiers: [%{mfa: {__MODULE__, :who, 1}, clauses: clauses}]
      }
    ]

    {:ok, shadow} = StructuralCoverage.start_shadow(classifiers)

    other =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    classifier = %{classifier_function: :who, source_function: :who, source_arity: 1}

    try do
      assert StructuralCoverage.classify(shadow, classifier, [self()], self()) ==
               {1, [{true, true}, {true, true}]}

      assert StructuralCoverage.classify(shadow, classifier, [other], self()) ==
               {2, [{true, false}, {true, true}]}
    after
      send(other, :stop)
      StructuralCoverage.stop_shadow(shadow)
    end
  end
end
