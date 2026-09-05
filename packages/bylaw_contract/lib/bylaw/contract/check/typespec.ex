defmodule Bylaw.Contract.Check.Typespec do
  @moduledoc """
  Observes input classes, range boundaries, and return alternatives declared by
  Elixir typespecs.
  """

  @behaviour Bylaw.Contract.Check

  alias Bylaw.Contract.Specs
  alias Bylaw.Contract.TypeMatcher

  @impl Bylaw.Contract.Check
  def init(modules, [], context) do
    loaded = Specs.load(modules)

    return_alternatives =
      Enum.reject(loaded.return_alternatives, fn alternative ->
        MapSet.member?(context.claims, {:return_alternatives, mfa(alternative)})
      end)

    loaded = %{loaded | return_alternatives: return_alternatives}
    input_targets_by_mfa = Enum.group_by(loaded.input_classes ++ loaded.boundaries, &mfa/1)
    return_alternatives_by_mfa = Enum.group_by(loaded.return_alternatives, &mfa/1)

    state =
      Map.merge(loaded, %{
        input_targets_by_mfa: input_targets_by_mfa,
        return_alternatives_by_mfa: return_alternatives_by_mfa,
        hits: %{},
        calls: %{},
        return_events: %{},
        unknown: MapSet.new()
      })

    claims =
      loaded.return_alternatives
      |> MapSet.new(&{:return_alternatives, mfa(&1)})

    {:ok, state,
     %{
       calls: input_targets_by_mfa |> Map.keys() |> MapSet.new(),
       returns: return_alternatives_by_mfa |> Map.keys() |> MapSet.new(),
       claims: claims
     }}
  end

  def init(_modules, opts, _context) do
    {:error, "unsupported typespec check options: #{inspect(opts)}"}
  end

  @impl Bylaw.Contract.Check
  def observe({:call, mfa, arguments}, state) do
    targets = Map.get(state.input_targets_by_mfa, mfa, [])

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

    %{state | hits: hits, unknown: unknown, calls: calls}
  end

  def observe({:return, mfa, value}, state) do
    alternatives = Map.get(state.return_alternatives_by_mfa, mfa, [])

    {hits, unknown} =
      Enum.reduce(alternatives, {state.hits, state.unknown}, fn alternative, {hits, unknown} ->
        case TypeMatcher.match(value, alternative.match_type) do
          :match -> {Map.update(hits, alternative.id, 1, &(&1 + 1)), unknown}
          :unknown -> {hits, MapSet.put(unknown, alternative.id)}
          :no_match -> {hits, unknown}
        end
      end)

    return_events =
      if Enum.empty?(alternatives) do
        state.return_events
      else
        Map.update(state.return_events, mfa, 1, &(&1 + 1))
      end

    %{state | hits: hits, unknown: unknown, return_events: return_events}
  end

  @impl Bylaw.Contract.Check
  def coverage(state) do
    Map.take(state, [
      :input_classes,
      :boundaries,
      :return_alternatives,
      :hits,
      :calls,
      :return_events,
      :unknown,
      :warnings
    ])
  end

  @impl Bylaw.Contract.Check
  def terminate(_state), do: :ok

  defp mfa(target), do: {target.module, target.function, target.arity}
end
