defmodule BylawBoundedStructuralPreparation do
  @moduledoc false
  @behaviour Bylaw.Contract.Check

  alias Bylaw.Contract.Check.FunctionClauses
  alias Bylaw.Contract.FunctionSelection

  @impl Bylaw.Contract.Check
  def init(modules, [unit_size: size], context) when is_integer(size) and size > 0 do
    groups =
      modules
      |> FunctionSelection.modules(Map.get(context, :only, :all))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.chunk_every(size)

    with {:ok, units, plan} <- prepare(groups, context) do
      by_module =
        for {group, index} <- Enum.with_index(groups),
            module <- group,
            into: %{},
            do: {module, index}

      {:ok,
       %{
         units: units |> Enum.with_index() |> Map.new(fn {unit, i} -> {i, unit} end),
         by_module: by_module
       }, plan}
    end
  end

  def init(_, opts, _), do: {:error, "unsupported bounded preparation options: #{inspect(opts)}"}

  @impl Bylaw.Contract.Check
  def observe(event, state), do: observe(event, self(), state)

  @impl Bylaw.Contract.Check
  def observe({:return, _, _}, _, state), do: state

  def observe({:call, {module, _, _}, _} = event, caller, state) do
    case Map.fetch(state.by_module, module) do
      {:ok, index} ->
        update_in(state.units[index], &FunctionClauses.observe(event, caller, &1))

      :error ->
        state
    end
  end

  @impl Bylaw.Contract.Check
  def coverage(state) do
    initial = %{
      clauses: [],
      arities: [],
      structural_modules: [],
      clause_outcomes: %{},
      unmatched_clause_calls: %{},
      arity_calls: %{}
    }

    state.units
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(initial, fn {_, unit}, combined ->
      Map.merge(combined, FunctionClauses.coverage(unit), fn
        _, before, after_unit when is_list(before) -> before ++ after_unit
        _, before, after_unit -> Map.merge(before, after_unit)
      end)
    end)
  end

  @impl Bylaw.Contract.Check
  def terminate(state) do
    Enum.each(state.units, fn {_, unit} -> FunctionClauses.terminate(unit) end)
  end

  defp prepare([], _context) do
    {:ok, [], %{calls: MapSet.new(), returns: MapSet.new(), claims: MapSet.new()}}
  end

  defp prepare([modules | rest], context) do
    with {:ok, unit, plan} <- FunctionClauses.init(modules, [], context) do
      try do
        :erlang.garbage_collect()

        case prepare(rest, context) do
          {:ok, prepared, remaining_plan} ->
            combined =
              Map.merge(plan, remaining_plan, fn _, left, right -> MapSet.union(left, right) end)

            {:ok, [unit | prepared], combined}

          {:error, _} = error ->
            FunctionClauses.terminate(unit)
            error
        end
      catch
        kind, reason ->
          FunctionClauses.terminate(unit)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end
end
