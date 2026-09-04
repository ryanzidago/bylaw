defmodule Bylaw.Contract do
  @moduledoc """
  Runtime observation derived from Elixir typespecs.

  Bylaw.Contract is intentionally narrower than code coverage. It observes calls
  made during a test run and reports which declared input classes and exact
  range boundaries were seen, plus which alternatives in top-level return
  unions were returned, and which user-authored function clauses were selected.
  It does not prove complete type or value-space coverage.
  """

  alias Bylaw.Contract.Report
  alias Bylaw.Contract.Tracer

  @doc "Starts tracing typespec-derived input classes and return alternatives in `modules`."
  @spec start(modules :: list(module())) :: GenServer.on_start()
  def start(modules) when is_list(modules), do: Tracer.start_link(modules)

  @doc "Stops a tracer and returns its coverage data."
  @spec stop(tracer :: pid()) :: map()
  def stop(tracer), do: Tracer.stop(tracer)

  @doc "Prints a human-readable report of actionable coverage gaps."
  @spec print_report(coverage :: map(), device :: IO.device()) :: :ok
  def print_report(coverage, device \\ :stdio), do: Report.print(coverage, device)

  @doc "Returns aggregate counters for a coverage result."
  @spec summary(coverage :: map()) :: map()
  def summary(coverage), do: Report.summary(coverage)
end
