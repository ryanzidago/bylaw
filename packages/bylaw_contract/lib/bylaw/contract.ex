defmodule Bylaw.Contract do
  @moduledoc """
  Runtime observations produced by explicitly selected contract checks.

  Bylaw.Contract is intentionally narrower than code coverage. It observes calls
  made during a test run and reports which declared input classes and exact
  range boundaries were seen, plus which alternatives in top-level return
  unions were returned, and which user-authored function clauses were selected.
  It does not prove complete type or value-space coverage.
  """

  alias Bylaw.Contract.Check
  alias Bylaw.Contract.Report
  alias Bylaw.Contract.Tracer

  @default_checks [Check.Typespec, Check.FunctionClauses]

  @typedoc "A check module or a check module with explicit options."
  @type check_spec :: module() | {module(), Check.opts()}

  @typedoc "The ordered contract checks to run."
  @type checks :: list(check_spec())

  @typedoc "Options controlling runtime contract observation."
  @type start_option :: {:checks, checks()} | {:max_trace_queue, pos_integer()}

  @doc "Starts the default typespec and structural checks for `modules`."
  @spec start(modules :: list(module())) :: GenServer.on_start()
  def start(modules) when is_list(modules), do: start(modules, [])

  @doc """
  Starts tracing with an explicit ordered check list.

  A check spec is either a module implementing `Bylaw.Contract.Check` or a
  `{check_module, opts}` tuple. The default check list enables
  `Bylaw.Contract.Check.Typespec` and `Bylaw.Contract.Check.FunctionClauses`.
  Passing an empty check list disables all observation.

  `:max_trace_queue` defaults to 4096 messages per check worker. Queues are
  checked before consuming trace events and independently every 5 milliseconds.
  Exceeding the threshold destroys that check's trace session and marks the result
  incomplete. Queues may overshoot between checks; this is not a byte-memory
  limit. Partial data remains available, but reports do not classify gaps from
  an incomplete observation.
  """
  @spec start(modules :: list(module()), opts :: list(start_option())) :: GenServer.on_start()
  def start(modules, opts) when is_list(modules) and is_list(opts) do
    opts = Keyword.validate!(opts, checks: @default_checks, max_trace_queue: 4096)
    limit = Keyword.fetch!(opts, :max_trace_queue)

    unless is_integer(limit) and limit > 0,
      do: raise(ArgumentError, "expected :max_trace_queue to be a positive integer")

    checks = opts |> Keyword.fetch!(:checks) |> normalize_checks!()

    Tracer.start_link(modules, checks, limit)
  end

  @doc """
  Stops a tracer and returns its coverage data.

  If any worker exceeded its queue budget, the map has `status: :incomplete`
  and an `:incomplete` list of check, reason, limit, and observed queue counts.
  Retained counters and targets then describe partial observation only.
  """
  @spec stop(tracer :: pid()) :: map()
  def stop(tracer), do: Tracer.stop(tracer)

  @doc "Prints actionable coverage gaps, or an incomplete-observation diagnostic."
  @spec print_report(coverage :: map(), device :: IO.device()) :: :ok
  def print_report(coverage, device \\ :stdio), do: Report.print(coverage, device)

  @doc "Returns aggregate counters, or incomplete status and reasons when observation aborted."
  @spec summary(coverage :: map()) :: map()
  def summary(coverage), do: Report.summary(coverage)

  defp normalize_checks!(checks) when is_list(checks) do
    checks
    |> Enum.reduce({MapSet.new(), []}, fn check_spec, {seen, normalized} ->
      {check, check_opts} = normalize_check_spec!(check_spec)

      if MapSet.member?(seen, check) do
        raise ArgumentError, "duplicate contract check: #{inspect(check)}"
      end

      validate_check!(check)
      {MapSet.put(seen, check), [{check, check_opts} | normalized]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp normalize_checks!(checks) do
    raise ArgumentError, "expected :checks to be a list, got: #{inspect(checks)}"
  end

  defp normalize_check_spec!(check) when is_atom(check), do: {check, []}

  defp normalize_check_spec!({check, opts})
       when is_atom(check) and is_list(opts) do
    if Keyword.keyword?(opts) do
      {check, opts}
    else
      invalid_check_spec!({check, opts})
    end
  end

  defp normalize_check_spec!(check_spec), do: invalid_check_spec!(check_spec)

  defp invalid_check_spec!(check_spec) do
    raise ArgumentError,
          "expected a contract check module or {module, keyword}, got: #{inspect(check_spec)}"
  end

  defp validate_check!(check) do
    callbacks = [{:init, 3}, {:observe, 2}, {:coverage, 1}, {:terminate, 1}]

    with {:module, ^check} <- Code.ensure_loaded(check),
         true <-
           Enum.all?(callbacks, fn {function, arity} ->
             function_exported?(check, function, arity)
           end) do
      :ok
    else
      _ ->
        raise ArgumentError, "expected #{inspect(check)} to implement Bylaw.Contract.Check"
    end
  end
end
