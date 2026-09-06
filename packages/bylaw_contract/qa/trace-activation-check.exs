defmodule BylawTraceActivationCheck do
  @moduledoc false
  @behaviour Bylaw.Contract.Check

  @impl Bylaw.Contract.Check
  def init(_modules, opts, _context) do
    state = %{
      events: [],
      retire_calls: Keyword.get(opts, :retire_calls, false),
      notify: Keyword.get(opts, :notify)
    }

    plan = %{
      calls: MapSet.new(Keyword.get(opts, :calls, [])),
      returns: MapSet.new(Keyword.get(opts, :returns, [])),
      claims: MapSet.new(),
      trace_scope: Keyword.get(opts, :trace_scope, :local),
      process_scope: Keyword.get(opts, :process_scope, :all)
    }

    {:ok, state, plan}
  end

  @impl Bylaw.Contract.Check
  def observe(event, state), do: observe(event, self(), state)

  @impl Bylaw.Contract.Check
  def observe(event, caller, state) do
    state = %{state | events: [{event, caller} | state.events]}

    case event do
      {:call, mfa, _} when state.retire_calls -> {:complete, state, [{:call, mfa}]}
      _ -> state
    end
  end

  @impl Bylaw.Contract.Check
  def coverage(state), do: %{events: Enum.reverse(state.events)}

  @impl Bylaw.Contract.Check
  def terminate(state) do
    if state.notify, do: send(state.notify, {:trace_activation_terminated, self()})
    :ok
  end
end
