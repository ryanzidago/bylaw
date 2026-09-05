defmodule Bylaw.Contract.Check.FunctionClauses do
  @moduledoc """
  Observes authored function clauses, guards, and callable arities.
  """

  @behaviour Bylaw.Contract.Check

  alias Bylaw.Contract.StructuralCoverage

  @impl Bylaw.Contract.Check
  def init(modules, [], _context) do
    loaded = StructuralCoverage.load(modules)

    with {:ok, shadow} <- StructuralCoverage.start_shadow(loaded.classifiers) do
      clauses_by_mfa = Enum.group_by(loaded.clauses, &mfa/1)

      classifiers_by_mfa =
        Map.new(
          for classifier <- loaded.classifiers,
              mfa_classifier <- classifier.mfa_classifiers do
            {_, function, arity} = mfa_classifier.mfa

            {mfa_classifier.mfa,
             %{
               classifier_function: classifier.classifier_function,
               source_function: function,
               source_arity: arity
             }}
          end
        )

      structural_mfas = MapSet.new(loaded.arities, &mfa/1)

      state =
        Map.merge(Map.delete(loaded, :classifiers), %{
          shadow: shadow,
          clauses_by_mfa: clauses_by_mfa,
          classifiers_by_mfa: classifiers_by_mfa,
          structural_mfas: structural_mfas,
          clause_outcomes: %{},
          unmatched_clause_calls: %{},
          arity_calls: %{}
        })

      {:ok, state, %{calls: structural_mfas, returns: MapSet.new(), claims: MapSet.new()}}
    end
  end

  def init(_modules, opts, _context) do
    {:error, "unsupported structural check options: #{inspect(opts)}"}
  end

  @impl Bylaw.Contract.Check
  def observe({:return, _mfa, _value}, state), do: state

  def observe({:call, mfa, arguments}, state) do
    clauses = Map.get(state.clauses_by_mfa, mfa, [])

    arity_calls =
      if MapSet.member?(state.structural_mfas, mfa) do
        Map.update(state.arity_calls, mfa, 1, &(&1 + 1))
      else
        state.arity_calls
      end

    {clause_outcomes, unmatched_clause_calls} = classify(state, clauses, arguments, mfa)

    %{
      state
      | arity_calls: arity_calls,
        clause_outcomes: clause_outcomes,
        unmatched_clause_calls: unmatched_clause_calls
    }
  end

  @impl Bylaw.Contract.Check
  def coverage(state) do
    Map.take(state, [
      :clauses,
      :clause_outcomes,
      :unmatched_clause_calls,
      :arities,
      :arity_calls,
      :modules
    ])
    |> Map.put(:structural_modules, state.modules)
    |> Map.delete(:modules)
  end

  @impl Bylaw.Contract.Check
  def terminate(state), do: StructuralCoverage.stop_shadow(state.shadow)

  defp classify(state, [], _arguments, _mfa),
    do: {state.clause_outcomes, state.unmatched_clause_calls}

  defp classify(state, clauses, arguments, mfa) do
    classifier = Map.fetch!(state.classifiers_by_mfa, mfa)
    {selected, raw_outcomes} = StructuralCoverage.classify(state.shadow, classifier, arguments)
    clause_outcomes = count_outcomes(clauses, raw_outcomes, selected, state.clause_outcomes)

    unmatched_clause_calls =
      if selected == :no_clause do
        Map.update(state.unmatched_clause_calls, mfa, 1, &(&1 + 1))
      else
        state.unmatched_clause_calls
      end

    {clause_outcomes, unmatched_clause_calls}
  end

  defp count_outcomes([], [], _selected, counts), do: counts

  defp count_outcomes([clause | clauses], [{head, guard} | outcomes], selected, counts) do
    head_count = boolean_count(head)
    guard_count = boolean_count(guard)
    rejection_count = boolean_count(clause.guarded? and head and not guard)
    selected_count = boolean_count(selected == clause.position)
    updated = Map.get(counts, clause.id)

    entry =
      if updated do
        %{
          head_matches: updated.head_matches + head_count,
          guard_passes: updated.guard_passes + guard_count,
          guard_rejections: updated.guard_rejections + rejection_count,
          selected: updated.selected + selected_count
        }
      else
        %{
          head_matches: head_count,
          guard_passes: guard_count,
          guard_rejections: rejection_count,
          selected: selected_count
        }
      end

    count_outcomes(clauses, outcomes, selected, Map.put(counts, clause.id, entry))
  end

  defp boolean_count(true), do: 1
  defp boolean_count(false), do: 0

  defp mfa(target), do: {target.module, target.function, target.arity}
end
