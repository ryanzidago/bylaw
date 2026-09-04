defmodule Bylaw.Contract.Tracer do
  @moduledoc false
  use GenServer

  alias Bylaw.Contract.Specs
  alias Bylaw.Contract.StructuralCoverage
  alias Bylaw.Contract.TypeMatcher

  @session_name :bylaw_contract_typespec_coverage
  @return_trace_match_spec [{:_, [], [{:return_trace}]}]

  @spec start_link(modules :: list(module())) :: GenServer.on_start()
  def start_link(modules), do: GenServer.start_link(__MODULE__, modules)

  @spec stop(tracer :: GenServer.server()) :: map()
  def stop(tracer), do: GenServer.call(tracer, :stop, :infinity)

  @impl GenServer
  def init(modules) do
    loaded = Specs.load(modules)
    structural = StructuralCoverage.load(modules)
    input_targets_by_mfa = Enum.group_by(loaded.input_classes ++ loaded.boundaries, &mfa/1)
    return_alternatives_by_mfa = Enum.group_by(loaded.return_alternatives, &mfa/1)
    clauses_by_mfa = Enum.group_by(structural.clauses, &mfa/1)

    classifiers_by_mfa =
      Map.new(
        for classifier <- structural.classifiers,
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

    structural_mfas = MapSet.new(structural.arities, &mfa/1)

    mfas =
      Enum.uniq(
        Map.keys(input_targets_by_mfa) ++
          Map.keys(return_alternatives_by_mfa) ++ MapSet.to_list(structural_mfas)
      )

    case start_trace_session(mfas, return_alternatives_by_mfa) do
      {:ok, session} ->
        case StructuralCoverage.start_shadow(structural.classifiers) do
          {:ok, shadow} ->
            {:ok,
             %{
               session: session,
               shadow: shadow,
               input_classes: loaded.input_classes,
               boundaries: loaded.boundaries,
               return_alternatives: loaded.return_alternatives,
               input_targets_by_mfa: input_targets_by_mfa,
               return_alternatives_by_mfa: return_alternatives_by_mfa,
               hits: %{},
               calls: %{},
               return_events: %{},
               unknown: MapSet.new(),
               clauses: structural.clauses,
               clauses_by_mfa: clauses_by_mfa,
               classifiers_by_mfa: classifiers_by_mfa,
               structural_mfas: structural_mfas,
               clause_outcomes: %{},
               unmatched_clause_calls: %{},
               arities: structural.arities,
               arity_calls: %{},
               structural_modules: structural.modules,
               warnings: loaded.warnings ++ structural.warnings
             }}

          {:error, reason} ->
            destroy_session(session)
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:trace, _, :call, {module, function, arguments}}, state)
      when is_list(arguments) do
    mfa = {module, function, Enum.count(arguments)}
    targets = Map.get(state.input_targets_by_mfa, mfa, [])
    clauses = Map.get(state.clauses_by_mfa, mfa, [])

    {hits, unknown} =
      Enum.reduce(targets, {state.hits, state.unknown}, fn target, {hits, unknown} ->
        value = Enum.at(arguments, target.argument - 1)

        case TypeMatcher.match(value, target.match_type) do
          :match -> {Map.update(hits, target.id, 1, &(&1 + 1)), unknown}
          :unknown -> {hits, MapSet.put(unknown, target.id)}
          :no_match -> {hits, unknown}
        end
      end)

    calls =
      if Enum.empty?(targets) do
        state.calls
      else
        Map.update(state.calls, mfa, 1, &(&1 + 1))
      end

    arity_calls =
      if MapSet.member?(state.structural_mfas, mfa) do
        Map.update(state.arity_calls, mfa, 1, &(&1 + 1))
      else
        state.arity_calls
      end

    {clause_outcomes, unmatched_clause_calls} =
      classify_clauses(state, clauses, module, function, arguments, mfa)

    {:noreply,
     %{
       state
       | hits: hits,
         unknown: unknown,
         calls: calls,
         clause_outcomes: clause_outcomes,
         unmatched_clause_calls: unmatched_clause_calls,
         arity_calls: arity_calls
     }}
  end

  def handle_info({:trace, _, :return_from, mfa, value}, state) do
    alternatives = Map.get(state.return_alternatives_by_mfa, mfa, [])

    {hits, unknown} = match_alternatives(alternatives, value, state.hits, state.unknown)

    {:noreply,
     %{
       state
       | hits: hits,
         unknown: unknown,
         return_events: Map.update(state.return_events, mfa, 1, &(&1 + 1))
     }}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_call(:stop, _, state) do
    state = stop_tracing_and_drain(state)
    StructuralCoverage.stop_shadow(state.shadow)

    coverage =
      Map.take(state, [
        :input_classes,
        :boundaries,
        :return_alternatives,
        :hits,
        :calls,
        :return_events,
        :unknown,
        :clauses,
        :clause_outcomes,
        :unmatched_clause_calls,
        :arities,
        :arity_calls,
        :structural_modules,
        :warnings
      ])

    {:stop, :normal, coverage, %{state | session: nil, shadow: nil}}
  end

  @impl GenServer
  def terminate(_, %{session: nil, shadow: shadow}) do
    StructuralCoverage.stop_shadow(shadow)
    :ok
  end

  def terminate(_, %{session: session, shadow: shadow}) do
    destroy_session(session)
    StructuralCoverage.stop_shadow(shadow)
    :ok
  end

  defp start_trace_session(mfas, return_alternatives_by_mfa) do
    with {:ok, session} <- create_session() do
      configure_session(session, mfas, return_alternatives_by_mfa)
    end
  end

  defp create_session do
    {:ok, :trace.session_create(@session_name, self(), [])}
  rescue
    error in ArgumentError ->
      {:error,
       "could not create a Bylaw.Contract isolated trace session: #{Exception.message(error)}"}
  end

  defp configure_session(session, mfas, return_alternatives_by_mfa) do
    Enum.each(mfas, fn mfa ->
      match_spec =
        if Map.has_key?(return_alternatives_by_mfa, mfa) do
          @return_trace_match_spec
        else
          true
        end

      :trace.function(session, mfa, match_spec, [:local])
    end)

    :trace.process(session, :all, true, [:call])
    :trace.process(session, :new, true, [:call])
    {:ok, session}
  rescue
    error in ArgumentError ->
      destroy_session(session)

      {:error,
       "could not configure the Bylaw.Contract trace session: #{Exception.message(error)}"}
  end

  defp stop_tracing_and_drain(%{session: session} = state) do
    :trace.process(session, :all, false, [:call])
    :trace.process(session, :new, false, [:call])
    reference = :trace.delivered(session, :all)
    state = drain_until_delivered(state, reference)
    destroy_session(session)
    %{state | session: nil}
  end

  defp drain_until_delivered(state, reference) do
    receive do
      {:trace_delivered, :all, ^reference} ->
        state

      {:trace, _, :call, {_, _, arguments}} = message when is_list(arguments) ->
        {:noreply, state} = handle_info(message, state)
        drain_until_delivered(state, reference)

      {:trace, _, :return_from, {_, _, _}, _} = message ->
        {:noreply, state} = handle_info(message, state)
        drain_until_delivered(state, reference)

      _ ->
        drain_until_delivered(state, reference)
    end
  end

  defp destroy_session(session) do
    :trace.session_destroy(session)
  catch
    :error, :badarg -> :ok
  end

  defp mfa(target), do: {target.module, target.function, target.arity}

  defp match_alternatives(alternatives, value, hits, unknown) do
    Enum.reduce(alternatives, {hits, unknown}, fn alternative, {hits, unknown} ->
      case TypeMatcher.match(value, alternative.match_type) do
        :match -> {Map.update(hits, alternative.id, 1, &(&1 + 1)), unknown}
        :unknown -> {hits, MapSet.put(unknown, alternative.id)}
        :no_match -> {hits, unknown}
      end
    end)
  end

  defp classify_clauses(state, [], _, _, _, _),
    do: {state.clause_outcomes, state.unmatched_clause_calls}

  defp classify_clauses(state, clauses, _, _, arguments, mfa) do
    classifier = Map.fetch!(state.classifiers_by_mfa, mfa)
    classification = StructuralCoverage.classify(state.shadow, classifier, clauses, arguments)

    clause_outcomes =
      Enum.reduce(classification.outcomes, state.clause_outcomes, fn {id, outcome}, outcomes ->
        Map.update(outcomes, id, new_outcome_counts(outcome), fn counts ->
          add_outcome(counts, outcome)
        end)
      end)

    unmatched_clause_calls =
      if classification.selected == :no_clause do
        Map.update(state.unmatched_clause_calls, mfa, 1, &(&1 + 1))
      else
        state.unmatched_clause_calls
      end

    {clause_outcomes, unmatched_clause_calls}
  end

  defp new_outcome_counts(outcome) do
    %{
      head_matches: boolean_count(outcome.head_matches?),
      guard_passes: boolean_count(outcome.guard_passes?),
      guard_rejections: boolean_count(outcome.guard_rejected?),
      selected: boolean_count(outcome.selected?)
    }
  end

  defp add_outcome(counts, outcome) do
    %{
      head_matches: counts.head_matches + boolean_count(outcome.head_matches?),
      guard_passes: counts.guard_passes + boolean_count(outcome.guard_passes?),
      guard_rejections: counts.guard_rejections + boolean_count(outcome.guard_rejected?),
      selected: counts.selected + boolean_count(outcome.selected?)
    }
  end

  defp boolean_count(true), do: 1
  defp boolean_count(false), do: 0
end
