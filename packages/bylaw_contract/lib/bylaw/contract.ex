defmodule Bylaw.Contract do
  @moduledoc """
  Finds the untested properties of functions.

  Line coverage tells you which lines ran. Bylaw.Contract tells you which
  declared properties of a function no test exercised:

    * **heads** - function clauses no test selected
    * **guards** - guards that never rejected a call
    * **types** - `@spec` argument alternatives, integer range boundaries and
      return alternatives no test produced

  Observation rewrites the loaded modules so each property bumps a counter in
  the calling process. It adds no processes, loses no data, and restores the
  original modules when it stops.

      report = Bylaw.Contract.observe([MyApp.Accounts], fn -> run_tests() end)
      Bylaw.Contract.Report.print(report)

  See `Bylaw.Contract.ExUnitFormatter` to observe a whole test suite.
  """

  alias Bylaw.Contract.Counters
  alias Bylaw.Contract.Instrumenter
  alias Bylaw.Contract.Property
  alias Bylaw.Contract.Report
  alias Bylaw.Contract.Specs

  @runtime_modules [
    __MODULE__,
    Bylaw.Contract.Baseline,
    Bylaw.Contract.CallCycles,
    Bylaw.Contract.ChangedCode,
    Bylaw.Contract.Counters,
    Bylaw.Contract.ExUnitFormatter,
    Bylaw.Contract.Instrumenter,
    Bylaw.Contract.Property,
    Bylaw.Contract.Report,
    Bylaw.Contract.Session,
    Bylaw.Contract.Specs,
    Bylaw.Contract.TypeExpansion,
    Bylaw.Contract.TypeMatcher
  ]

  @active_key {__MODULE__, :active_session}
  @replaced_reason "the module was replaced by other code during observation"

  defmodule Session do
    @moduledoc false

    @type t :: %__MODULE__{
            token: integer(),
            results: list(map()),
            warnings: list(String.t())
          }

    defstruct [:token, results: [], warnings: []]
  end

  @doc """
  Observes `modules` while `fun` runs and returns a `Bylaw.Contract.Report`.

  Raises when another observation is already active.
  """
  @spec observe(modules :: list(module()), fun :: (-> term())) :: Report.t()
  def observe(modules, fun) when is_list(modules) and is_function(fun, 0) do
    case start(modules) do
      {:ok, session} ->
        try do
          fun.()
          stop(session)
        catch
          kind, reason ->
            stop(session)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

      {:error, :session_active} ->
        raise ArgumentError, "another Bylaw.Contract observation is already active"
    end
  end

  @doc """
  Starts observing `modules`.

  Only one observation can be active at a time. Modules that cannot be observed
  produce warnings in the final report instead of failing the start.
  """
  @spec start(modules :: list(module())) :: {:ok, Session.t()} | {:error, :session_active}
  def start(modules) when is_list(modules) do
    token = System.unique_integer([:positive, :monotonic])

    case claim(token) do
      :ok ->
        {:ok, instrument(Enum.uniq(modules), token)}

      :error ->
        {:error, :session_active}
    end
  end

  @doc "Stops observing, restores the original modules, and returns the report."
  @spec stop(session :: Session.t()) :: Report.t()
  def stop(%Session{token: token} = session) do
    results = Enum.map(session.results, &Map.put(&1, :replaced?, replaced?(&1)))
    properties = Enum.flat_map(results, &read_properties/1)

    restore_warnings =
      Enum.flat_map(results, fn
        %{original: nil} -> []
        %{replaced?: true} -> []
        %{original: original} -> restore(original)
      end)

    Counters.delete_session(token)
    release(token)

    %Report{
      properties: Enum.sort_by(properties, &sort_key/1),
      warnings:
        session.warnings ++
          Enum.flat_map(results, & &1.warnings) ++ restore_warnings ++ replaced_warnings(results)
    }
  end

  defp replaced?(%{module: module, loaded_md5: loaded_md5}),
    do: Instrumenter.replaced?(module, loaded_md5)

  defp replaced_warnings(results) do
    for %{replaced?: true, module: module} <- results,
        do:
          "#{inspect(module)} was replaced by other code during observation; " <>
            "its properties could not be assessed"
  end

  defp instrument(modules, token) do
    {runtime, observed} = Enum.split_with(modules, &(&1 in @runtime_modules))
    specs = Specs.load(observed)

    targets =
      Enum.group_by(
        tag(specs.input_classes, :argument_class) ++
          tag(specs.boundaries, :argument_boundary) ++
          tag(specs.return_alternatives, :return_alternative),
        & &1.module
      )

    results =
      observed
      |> Task.async_stream(
        fn module ->
          result = Instrumenter.instrument(module, Map.get(targets, module, []), token)
          Map.put(result, :module, module)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    sessions =
      for %{counters: counters, module: module, descriptors: descriptors} <- results,
          counters != nil,
          into: %{},
          do: {module, {counters, descriptors}}

    Counters.put_session(token, sessions)

    runtime_warnings =
      Enum.map(runtime, &"#{inspect(&1)} is observer runtime code and cannot be observed")

    %Session{token: token, results: results, warnings: specs.warnings ++ runtime_warnings}
  end

  defp tag(targets, kind), do: Enum.map(targets, &Map.put(&1, :kind, kind))

  defp read_properties(%{replaced?: true, properties: properties}),
    do: Enum.map(properties, &Instrumenter.mark_unassessable(&1, @replaced_reason))

  defp read_properties(%{counters: nil, properties: properties}), do: properties

  defp read_properties(%{counters: counters, properties: properties}),
    do: Enum.map(properties, &read_property(&1, counters))

  defp read_property(%Property{status: :unassessable} = property, _counters), do: property
  defp read_property(%Property{slot: nil} = property, _counters), do: property

  defp read_property(%Property{} = property, counters) do
    count = :counters.get(counters, property.slot)
    unknown? = property.unknown_slot != nil and :counters.get(counters, property.unknown_slot) > 0

    status =
      cond do
        count > 0 -> :observed
        unknown? -> :unassessable
        true -> :missed
      end

    reason =
      if status == :unassessable do
        "the observed values could not be assessed"
      end

    %{property | count: count, status: status, reason: reason}
  end

  defp restore(original) do
    case Instrumenter.restore(original) do
      :ok -> []
      {:error, reason} -> [reason]
    end
  end

  defp sort_key(property),
    do:
      {property.module, property.function, property.arity, property.kind, property.clause || 0,
       property.label || ""}

  defp claim(token) do
    :global.trans({@active_key, self()}, fn ->
      case :persistent_term.get(@active_key, nil) do
        nil ->
          :persistent_term.put(@active_key, token)
          :ok

        _active ->
          :error
      end
    end)
  end

  defp release(token) do
    :global.trans({@active_key, self()}, fn ->
      if :persistent_term.get(@active_key, nil) == token do
        :persistent_term.erase(@active_key)
      end
    end)

    :ok
  end

  @doc false
  @spec runtime_modules() :: list(module())
  def runtime_modules, do: @runtime_modules
end
